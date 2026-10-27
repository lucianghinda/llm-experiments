#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the experiment in Apple containers: one fresh container per trial, no
# host agent configuration of any kind. The host only orchestrates.
#
#   ruby scripts/container_runner.rb <agent> <reps> [arm ...]
#
# Deliberately light on the machine: a 2 GB / 2 CPU envelope, one container at a
# time, the trial directory deleted after its commit message is read, and no
# image build (the pinned CLIs are mounted from ~/.llmx/tools).

require "base64"
require "fileutils"
require "json"
require_relative "arms"
require_relative "../../containers/scripts/lib/kit"

EXP   = File.expand_path("..", __dir__)
WORK  = ENV.fetch("GCC_WORK")
AGENT = ARGV[0] or abort "usage: container_runner.rb <agent> <reps> [arm ...]"
REPS  = (ARGV[1] || "2").to_i
ONLY  = ARGV[2..].to_a

TOOLS = File.expand_path(ENV.fetch("GCC_TOOLS", "~/.llmx/tools"))
PROMPT = "Commit the staged change."

MODELS = {
  "claude" => ENV.fetch("GCC_CLAUDE_MODEL", "sonnet"),
  "codex" => ENV.fetch("GCC_CODEX_MODEL", ""),
  "opencode" => ENV.fetch("GCC_OPENCODE_MODEL", "openai/gpt-5.3-codex-spark")
}.freeze

TABLES = { "claude" => CLAUDE_ARMS, "codex" => CODEX_ARMS, "opencode" => OPENCODE_ARMS }.freeze

# The arm table uses Ruby symbols and a couple of host-only conventions; the
# container receives plain JSON.
def payload(name, arm, rep)
  settings =
    if arm[:settings] == :hook
      hook_settings("/workspace/trial/pretooluse.rb")
    else
      arm[:settings] || {}
    end

  {
    "name" => name, "rep" => rep, "desc" => arm[:desc],
    "settings" => settings,
    "files" => arm[:files] || {},
    "githook" => arm[:githook],
    "hook" => (arm[:settings] == :hook || arm[:codex_hook]) ? PRETOOLUSE_HOOK : nil,
    "codex_hook" => !arm[:codex_hook].nil?,
    "codex_config" => Array(arm[:codex_config]).map { |c|
      c.sub("%<rules>s", COMMIT_RULES.to_json)
       .sub("%<instr_file>s", "/workspace/trial/instructions.md".to_json)
    },
    "codex_flags" => Array(arm[:codex_flags]),
    # opencode reads CLAUDE.md unless told not to; only that arm wants it on.
    "read_claude_md" => (arm[:env] || {}).key?("OPENCODE_DISABLE_CLAUDE_CODE")
  }
end

def run_trial(agent, name, arm, rep)
  out_dir = File.join(EXP, "runs-container", agent)
  FileUtils.mkdir_p(out_dir)
  msg_path = File.join(out_dir, format("%s.%02d.txt", name, rep))
  return :skip if File.exist?(msg_path)

  trial = File.join(WORK, "trial")
  FileUtils.rm_rf(trial)
  FileUtils.mkdir_p(trial)
  # model_instructions_file needs a real file at a container path.
  File.write(File.join(trial, "instructions.md"), COMMIT_RULES)

  data = payload(name, arm, rep)
  tool = arm[:claude_tool].to_s
  env_args = [
    "--env", "GCC_AGENT=#{agent}",
    "--env", "GCC_MODEL=#{arm[:claude_model] || MODELS.fetch(agent)}",
    "--env", "GCC_PROMPT_B64=#{Base64.strict_encode64(PROMPT)}",
    "--env", "GCC_ARM_B64=#{Base64.strict_encode64(JSON.generate(data))}",
    "--env", "GCC_CLAUDE_TOOL=#{tool}"
  ]

  ok = system("container", "run", "--rm",
              *Kit.run_args(memory: ENV.fetch("GCC_MEMORY", "2g"),
                            cpus: ENV.fetch("GCC_CPUS", "2")),
              "--volume", "#{trial}:/workspace/trial",
              "--volume", "#{File.join(EXP, 'scripts')}:/gcc-scripts",
              "--volume", "#{TOOLS}:/tools",
              *env_args,
              Kit::BASE_IMAGE,
              "bash", "-lc", "exec ruby /gcc-scripts/container_trial.rb",
              out: File::NULL, err: File::NULL)

  produced = File.join(trial, "out", "message.txt")
  meta = File.join(trial, "out", "meta.json")
  if File.exist?(produced) && File.exist?(meta)
    FileUtils.cp(produced, msg_path)
    FileUtils.cp(meta, File.join(out_dir, format("%s.%02d.json", name, rep)))
    result = JSON.parse(File.read(meta))["committed"] ? :ok : :nocommit
  else
    result = ok ? :nooutput : :containerfail
  end

  FileUtils.rm_rf(trial)
  result
end

Kit.ensure_system_started!
abort "base image missing" unless Kit.image_exists?(Kit::BASE_IMAGE)

arms = TABLES.fetch(AGENT) { abort "unknown agent #{AGENT}" }
(ONLY.empty? ? arms.keys : ONLY).each do |name|
  arm = arms[name] or abort "no such arm: #{name}"
  (1..REPS).each do |rep|
    puts format("%-9s %-30s rep %-2d %s", AGENT, name, rep, run_trial(AGENT, name, arm, rep))
    $stdout.flush
  end
end
