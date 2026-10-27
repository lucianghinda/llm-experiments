#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs INSIDE a trial container. container_runner.rb mounts this and starts it;
# it never executes on the host.
#
#   /workspace/trial   the only writable mount: fixture, config and results
#   /gcc-scripts       this experiment's scripts (fixture.rb)
#   /tools             pinned agent CLIs, newer than the base image's
#   ~/.agent-auth      the credential seed, per the kit convention
#
# The seed is READ ONLY: only the credential files are copied into a
# container-local config dir, so no host-persisted state is shared between
# trials and no arm inherits another arm's settings.

require "base64"
require "fileutils"
require "json"
require "open3"

TRIAL = "/workspace/trial"
REPO  = File.join(TRIAL, "repo")
OUT   = File.join(TRIAL, "out")
SEED  = "/home/agent/.agent-auth"

CLAUDE   = "/tools/#{(ENV["GCC_CLAUDE_TOOL"].to_s.empty? ? "claude-latest" : ENV["GCC_CLAUDE_TOOL"])}/node_modules/.bin/claude"
CODEX    = "/tools/gcc/node_modules/.bin/codex"
OPENCODE = "/tools/gcc/node_modules/.bin/opencode"

agent  = ENV.fetch("GCC_AGENT")
model  = ENV["GCC_MODEL"].to_s
prompt = Base64.strict_decode64(ENV.fetch("GCC_PROMPT_B64"))
arm    = JSON.parse(Base64.strict_decode64(ENV.fetch("GCC_ARM_B64")))

FileUtils.mkdir_p(OUT)

# The repository is built here, by the container's own git, so no host git
# version or host config can reach it.
system("ruby", "/gcc-scripts/fixture.rb", REPO, out: File::NULL) or abort "fixture failed"

(arm["files"] || {}).each do |rel, body|
  path = File.join(REPO, rel)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, body)
end

if arm["githook"]
  hook = File.join(REPO, ".git", "hooks", "prepare-commit-msg")
  File.write(hook, arm["githook"])
  FileUtils.chmod(0o755, hook)
end

hook_script = File.join(TRIAL, "pretooluse.rb")
File.write(hook_script, arm["hook"]) if arm["hook"]

if arm["codex_hook"]
  FileUtils.mkdir_p(File.join(REPO, ".codex"))
  File.write(File.join(REPO, ".codex", "hooks.json"), JSON.pretty_generate(
    { "hooks" => { "PreToolUse" => [{ "hooks" => [
      { "type" => "command", "command" => "ruby #{hook_script}", "timeout" => 15 }] }] } }))
end

def seed_copy(from, to, names)
  FileUtils.mkdir_p(to)
  names.each do |n|
    src = File.join(from, n)
    FileUtils.cp(src, File.join(to, n)) if File.exist?(src)
  end
end

env = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null" }
settings = {}

case agent
when "claude"
  cfg = "/home/agent/cfg-claude"
  # Credentials and onboarding state only. No settings.json, no projects,
  # no plugins: this arm's settings must be the only ones in play.
  seed_copy(File.join(SEED, "claude"), cfg, [".credentials.json", ".claude.json"])
  settings = arm["settings"] || {}
  settings_path = File.join(TRIAL, "settings.json")
  File.write(settings_path, JSON.pretty_generate(settings))
  File.write("/tmp/empty-mcp.json", '{"mcpServers":{}}')
  env["CLAUDE_CONFIG_DIR"] = cfg
  cmd = [CLAUDE, "-p", prompt, "--model", model,
         "--settings", settings_path,
         "--strict-mcp-config", "--mcp-config", "/tmp/empty-mcp.json",
         "--permission-mode", "bypassPermissions",
         "--no-session-persistence"]

when "codex"
  home = "/home/agent/codex-home"
  seed_copy(File.join(SEED, "codex"), home, ["auth.json"])   # never config.toml
  env["CODEX_HOME"] = home
  cmd = [CODEX, "exec", "--skip-git-repo-check", "--sandbox", "workspace-write",
         "-c", 'approval_policy="never"',
         # workspace-write refuses to write .git/index.lock, so no trial could
         # ever commit unless the repo's own .git is named writable.
         "-c", "sandbox_workspace_write.writable_roots=[#{File.join(REPO, '.git').to_json}]"]
  cmd += ["-m", model] unless model.empty?
  Array(arm["codex_config"]).each { |c| cmd += ["-c", c] }
  cmd += Array(arm["codex_flags"])
  cmd << prompt

when "opencode"
  data = "/home/agent/oc-data"
  seed_copy(File.join(SEED, "opencode"), File.join(data, "opencode"), ["auth.json"])
  env["XDG_DATA_HOME"] = data
  env["XDG_CONFIG_HOME"] = "/home/agent/oc-config"
  FileUtils.mkdir_p(env["XDG_CONFIG_HOME"])
  # opencode falls back to CLAUDE.md unless told not to; the arm decides.
  env["OPENCODE_DISABLE_CLAUDE_CODE"] = "1" unless arm["read_claude_md"]
  # opencode does not inherit the spawn cwd and must be given --dir.
  cmd = [OPENCODE, "run", "--pure", "--auto", "--dir", REPO, "-m", model, prompt]
else
  abort "unknown agent #{agent}"
end

before = `git -C #{REPO} rev-parse HEAD`.strip
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
stdout, stderr, status = Open3.capture3(env, *cmd, chdir: REPO, stdin_data: "")
seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
after = `git -C #{REPO} rev-parse HEAD`.strip

committed = before != after
message = committed ? `git -C #{REPO} log -1 --pretty=%B`.sub(/\n+\z/, "\n") : ""

versions = {
  "claude" => `#{CLAUDE} --version 2>/dev/null`.strip,
  "codex" => `#{CODEX} --version 2>/dev/null`.strip,
  "opencode" => `#{OPENCODE} --version 2>/dev/null`.strip,
  "git" => `git --version`.strip
}

# Anthropic rotates refresh tokens. The refresh happens in the container-local
# copy, so without writing it back the next trial replays a dead token and the
# whole sweep fails after the first refresh. Only the credential file goes
# back; settings, projects and sessions stay container-local.
if agent == "claude"
  fresh = File.join("/home/agent/cfg-claude", ".credentials.json")
  FileUtils.cp(fresh, File.join(SEED, "claude", ".credentials.json")) if File.exist?(fresh)
end

File.write(File.join(OUT, "message.txt"), message)
File.write(File.join(OUT, "meta.json"), JSON.pretty_generate({
  "agent" => agent, "arm" => arm["name"], "rep" => arm["rep"],
  "desc" => arm["desc"], "settings" => settings,
  "codex_config" => arm["codex_config"],
  "model" => model, "versions" => versions,
  "committed" => committed, "exit" => status.exitstatus, "seconds" => seconds,
  "command" => cmd.join(" "),
  "stderr_tail" => stderr.to_s.split("\n").last(3),
  "agent_stdout_tail" => stdout.to_s.split("\n").last(2)
}))
