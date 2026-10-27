#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs one arm of the git-commit-controls experiment and keeps only the commit
# message. The throwaway repo is deleted after every trial, so the disk cost of
# the whole experiment is the few hundred bytes each message takes.
#
#   ruby runner.rb <agent> <reps> [arm ...]

require "json"
require "fileutils"
require "open3"
require_relative "arms"

EXP   = File.expand_path("..", __dir__)
WORK  = ENV.fetch("GCC_WORK")            # scratch dir, outside the repo
AGENT = ARGV[0] or abort "usage: runner.rb <agent> <reps> [arm ...]"
REPS  = (ARGV[1] || "2").to_i
ONLY  = ARGV[2..].to_a

# Resolve the real CLI, skipping cmux wrapper shims: those inject their own
# --settings and --session-id, so a trial run through one measures the wrapper.
def self.real_bin(name, env_key)
  from_env = ENV[env_key].to_s
  return from_env unless from_env.empty?
  dirs = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).reject { |d| d.include?("cmux-cli-shims") }
  dirs.map { |d| File.join(d, name) }.find { |c| File.executable?(c) } || name
end

CLAUDE_BIN   = real_bin("claude", "GCC_CLAUDE_BIN")
CODEX_BIN    = real_bin("codex", "GCC_CODEX_BIN")
OPENCODE_BIN = real_bin("opencode", "GCC_OPENCODE_BIN")

PROMPT = "Commit the staged change."

# Claude Code exports these into every child process; a nested run must not
# inherit the parent session's identity or messaging socket.
SCRUB = %w[CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID
           CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_MESSAGING_SOCKET
           CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_BRIDGE_SESSION_ID
           CLAUDE_EFFORT CLAUDE_PID AI_AGENT CLAUDE_CODE_EXECPATH].freeze

# Neutralise the host's git config so no commit template or hooksPath leaks in.
BASE_ENV = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null" }.freeze

def arms_for(agent)
  case agent
  when "claude" then CLAUDE_ARMS
  when "codex" then CODEX_ARMS
  when "opencode" then OPENCODE_ARMS
  else abort "unknown agent #{agent}"
  end
end

# The rules are handed to Codex as a TOML string; JSON escaping is compatible.
def codex_overrides(arm, work)
  Array(arm[:codex_config]).map do |c|
    c.sub("%<rules>s", COMMIT_RULES.to_json)
     .sub("%<instr_file>s", File.join(work, "instructions.md").to_json)
  end
end

def build_command(agent, arm, repo, settings_path, name)
  case agent
  when "claude"
    [CLAUDE_BIN, "-p", PROMPT,
     "--model", (arm[:claude_model] || ENV.fetch("GCC_CLAUDE_MODEL", "sonnet")),
     "--settings", settings_path,
     "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
     "--permission-mode", "bypassPermissions",
     "--no-session-persistence"]
  when "codex"
    cmd = [CODEX_BIN, "exec", "--skip-git-repo-check",
           "--sandbox", "workspace-write",
           "-c", "approval_policy=\"never\""]
    cmd += ["-c", "sandbox_workspace_write.writable_roots=[#{File.join(repo, ".git").to_json}]"]
    model = ENV["GCC_CODEX_MODEL"].to_s
    cmd += ["-m", model] unless model.empty?
    codex_overrides(arm, WORK).each { |c| cmd += ["-c", c] }
    cmd += Array(arm[:codex_flags])
    cmd + [PROMPT]
  when "opencode"
    [OPENCODE_BIN, "run", "--pure", "--auto", "--dir", repo,
     "-m", ENV.fetch("GCC_OPENCODE_MODEL", "openai/gpt-5.4"),
     PROMPT]
  end
end

def run_trial(agent, name, arm, rep)
  out_dir = File.join(EXP, "runs", agent)
  FileUtils.mkdir_p(out_dir)
  msg_path = File.join(out_dir, format("%s.%02d.txt", name, rep))
  meta_path = File.join(out_dir, format("%s.%02d.json", name, rep))
  return :skip if File.exist?(msg_path)

  repo = File.join(WORK, "work")
  system("ruby", File.join(EXP, "scripts", "fixture.rb"), repo, out: File::NULL) or abort "fixture failed"

  # Arm files land inside the repo but are NOT staged: only the cart fix is.
  (arm[:files] || {}).each do |rel, body|
    path = File.join(repo, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  if arm[:codex_hook]
    script = File.join(WORK, "pretooluse.rb")
    File.write(script, PRETOOLUSE_HOOK)
    FileUtils.mkdir_p(File.join(repo, ".codex"))
    File.write(File.join(repo, ".codex", "hooks.json"), JSON.pretty_generate(
      { "hooks" => { "PreToolUse" => [ { "hooks" => [ { "type" => "command",
        "command" => "ruby #{script}", "timeout" => 15 } ] } ] } }))
  end

  if arm[:githook]
    hook = File.join(repo, ".git", "hooks", "prepare-commit-msg")
    File.write(hook, arm[:githook])
    FileUtils.chmod(0o755, hook)
  end

  settings_path = File.join(WORK, "settings.json")
  settings =
    if arm[:settings] == :hook
      script = File.join(WORK, "pretooluse.rb")
      File.write(script, arm[:hook])
      hook_settings(script)
    else
      (arm[:settings] || {}).dup
    end
  # Host SessionStart/SessionEnd hooks inject memory context; off unless the arm is about hooks.
  settings["disableAllHooks"] = true unless arm[:settings] == :hook
  File.write(settings_path, JSON.pretty_generate(settings))

  env = BASE_ENV.dup
  SCRUB.each { |k| env[k] = nil }
  case agent
  when "codex"
    env["CODEX_HOME"] = File.join(WORK, "codex-home")
    File.write(File.join(WORK, "instructions.md"), COMMIT_RULES)
  when "opencode"
    home = File.join(WORK, "oc-home")
    FileUtils.mkdir_p(File.join(home, "config"))
    env["HOME"] = home
    env["XDG_CONFIG_HOME"] = File.join(home, "config")
    env["XDG_DATA_HOME"] = File.expand_path("~/.local/share")
    env["XDG_CACHE_HOME"] = File.expand_path("~/.cache")
    env["OPENCODE_DISABLE_CLAUDE_CODE"] = "1"
  end
  env.merge!(arm[:env] || {})

  before = `git -C #{repo} rev-parse HEAD`.strip
  started = Time.now
  cmd = build_command(agent, arm, repo, settings_path, name)
  stdout, stderr, status = Open3.capture3(env, *cmd, chdir: repo, stdin_data: "")
  elapsed = (Time.now - started).round(1)

  after = `git -C #{repo} rev-parse HEAD`.strip
  committed = before != after
  message = committed ? `git -C #{repo} log -1 --pretty=%B`.sub(/\n+\z/, "\n") : ""

  File.write(msg_path, message)
  File.write(meta_path, JSON.pretty_generate({
    "agent" => agent, "arm" => name, "rep" => rep,
    "desc" => arm[:desc], "settings" => settings,
    "codex_config" => (agent == "codex" ? codex_overrides(arm, WORK) : nil),
    "committed" => committed, "exit" => status.exitstatus,
    "seconds" => elapsed, "command" => cmd.join(" ").gsub(Dir.home, "~"),
    "model" => (arm[:claude_model] || ENV["GCC_CLAUDE_MODEL"] || ENV["GCC_CODEX_MODEL"] || ENV["GCC_OPENCODE_MODEL"]),
    "stderr_tail" => stderr.to_s.split("\n").last(3),
    "agent_stdout_tail" => stdout.to_s.split("\n").last(2)
  }))

  FileUtils.rm_rf(repo)
  committed ? :ok : :nocommit
end

arms = arms_for(AGENT)
selected = ONLY.empty? ? arms.keys : ONLY
selected.each do |name|
  arm = arms[name] or abort "no such arm: #{name}"
  (1..REPS).each do |rep|
    result = run_trial(AGENT, name, arm, rep)
    puts format("%-10s %-30s rep %d  %s", AGENT, name, rep, result)
    $stdout.flush
  end
end
