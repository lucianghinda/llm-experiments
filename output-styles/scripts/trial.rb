#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs INSIDE a trial container. run_grid.rb mounts this file read-only and
# starts it; it is never executed on the host.
#
# One trial = one fresh container = one `claude -p` session. Everything the
# trial needs arrives through read-only mounts and environment variables:
#
#   /bundles           git bundles of the app repos (read-only)
#   /styles            the custom output-style files from the repo (read-only)
#   /tools/claude      a pinned Claude Code install, newer than the base image's
#   ~/.agent-auth      the credential seed (mounted by the kit convention)
#   /results           the only writable mount; everything observed lands here
#
# The credential seed is copied into a container-local config dir first, so the
# mounted store is only ever read. See containers/README.md, "a seed, not a
# home".

require "base64"
require "fileutils"
require "json"
require "open3"

APP    = "/workspace/app"
CFG    = "/home/agent/claude-cfg"
SEED   = "/home/agent/.agent-auth/claude"
CLAUDE = "/tools/claude/node_modules/.bin/claude"

def env!(key)
  value = ENV[key].to_s
  abort "#{key} required" if value.empty?
  value
end

bundle     = env!("LLMX_BUNDLE")
prompt     = Base64.strict_decode64(env!("LLMX_PROMPT_B64"))
model      = env!("LLMX_MODEL")
timeout_s  = ENV.fetch("LLMX_TIMEOUT", "1200")
style_name = ENV["LLMX_STYLE_NAME"].to_s
style_file = ENV["LLMX_STYLE_FILE"].to_s

# Credentials: copy the three files that carry auth and onboarding state,
# nothing else. History, projects and sessions stay on the host.
FileUtils.mkdir_p(CFG)
[".credentials.json", ".claude.json", "settings.json"].each do |f|
  src = File.join(SEED, f)
  FileUtils.cp(src, File.join(CFG, f)) if File.exist?(src)
end

# The app arrives as committed history only. Untracked host junk cannot follow.
system("git", "clone", "-q", "--branch", "main", "/bundles/#{bundle}", APP) or abort "clone failed"
app_sha = `git -C #{APP} rev-parse HEAD`.strip

# The style under test, if any. Built-in styles need only the setting; custom
# ones also need their file present at the project level.
#
# An unknown style name is NOT an error: Claude Code falls back to Default and
# says nothing, on stderr or in --debug. A typo would therefore produce a cell
# that looks like a clean null result and is really a control run. For custom
# styles the name in the frontmatter is the name the setting has to use, so
# that pair is checked here and the trial dies rather than lie.
unless style_name.empty?
  claude_dir = File.join(APP, ".claude")
  unless style_file.empty?
    src = "/styles/#{style_file}"
    declared = File.read(src)[/^name:\s*(.+?)\s*$/, 1]
    abort "style file #{style_file} declares name #{declared.inspect}, trial asked for #{style_name.inspect}" unless declared == style_name

    FileUtils.mkdir_p(File.join(claude_dir, "output-styles"))
    FileUtils.cp(src, File.join(claude_dir, "output-styles", style_file))
  end
  FileUtils.mkdir_p(claude_dir)
  File.write(File.join(claude_dir, "settings.local.json"), JSON.pretty_generate({ "outputStyle" => style_name }))
end

# Both app repos commit a .mcp.json whose servers run through `bundle exec`.
# No gems are installed here, so those servers would fail noisily. An empty
# strict config keeps the session at zero MCP, which is also the clean-room
# guarantee this kit exists for.
File.write("/tmp/empty-mcp.json", '{"mcpServers":{}}')

version = `#{CLAUDE} --version`.strip

cmd = [
  "timeout", timeout_s,
  CLAUDE, "-p", prompt,
  "--model", model,
  "--output-format", "json",
  "--strict-mcp-config", "--mcp-config", "/tmp/empty-mcp.json"
]

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
out, err, status = Open3.capture3({ "CLAUDE_CONFIG_DIR" => CFG }, *cmd, chdir: APP)
seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)

File.write("/results/output.json", out)
File.write("/results/stderr.txt", err)
File.write("/results/meta.json", JSON.pretty_generate({
  "claude_version" => version,
  "model_requested" => model,
  "app_bundle" => bundle,
  "app_sha" => app_sha,
  "style_name" => style_name.empty? ? nil : style_name,
  "style_file" => style_file.empty? ? nil : style_file,
  "prompt" => prompt,
  "exit" => status.exitstatus,
  "seconds" => seconds,
  "finished_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
}))

exit(status.exitstatus || 1)
