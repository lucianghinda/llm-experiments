#!/usr/bin/env ruby
# frozen_string_literal: true

# Measures what an agent CLI carries into its first request, before it does any
# work.
#
#   ruby startup-context/scripts/probe.rb --all --repeats 3
#   ruby startup-context/scripts/probe.rb --agent claude --condition host-full
#   ruby startup-context/scripts/probe.rb --list
#
# The task is "Reply with exactly: OK". Nothing in a configuration can help with
# it and no tool call can serve it, so everything the run reports as input is
# overhead: system prompt, tool schemas, skill and command catalogues, memory
# files, and whatever the session hooks injected.
#
# Two things this script is careful about, both of which would quietly ruin the
# numbers:
#
# 1. `claude` and `codex` on PATH may be shims. A terminal multiplexer, a
#    version manager or a wrapper can sit in front of the real binary and add
#    its own flags. The probe resolves the real executable itself and records
#    the path it used, because a measurement of somebody else's wrapper is not
#    a measurement of this machine.
#
# 2. A host run must not write into the user's own state. Sessions are not
#    persisted, and no condition writes to the real config directory.
#
# Output lands in results-raw/<agent>/<condition>/<utc timestamp>/ as the raw
# JSONL exactly as the CLI produced it, plus stderr and a meta.json describing
# how the run was made. Nothing is summarised here; parse_probe.rb does that.

require "fileutils"
require "json"
require "open3"
require "time"
require "tmpdir"
require_relative "../../containers/scripts/lib/kit"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
PROMPT = File.read(File.join(EXPERIMENT_DIR, "prompts", "probe.txt")).strip
RAW = File.join(EXPERIMENT_DIR, "results-raw")
TIMEOUT = Integer(ENV.fetch("LLMX_PROBE_TIMEOUT", "300"))

# Both models are pinned. A condition that changed the model would change the
# system prompt underneath the thing being measured, and the `--ignore-user-config`
# condition would otherwise silently fall back to a different default model.
CLAUDE_MODEL = ENV.fetch("LLMX_CLAUDE_MODEL", "sonnet")
CODEX_MODEL = ENV.fetch("LLMX_CODEX_MODEL", "gpt-5.6-sol")

# A real project directory, used only by the `host-project` conditions. Passed
# in rather than hard-coded, so no absolute path from one machine enters the
# repository.
PROJECT_DIR = ENV["LLMX_PROJECT_DIR"]

# The condition list lives in conditions.rb, shared with report.rb.
require_relative "conditions"


# --- resolving the real binary -----------------------------------------------
#
# `command -v` is not enough: shim directories are put at the front of PATH on
# purpose. Any PATH entry whose name says it holds shims is skipped, and the
# path actually used is recorded in meta.json so a run can be checked later.
SHIM_MARKERS = %w[cmux-cli-shims shims .shim].freeze

def real_binary(name)
  override = ENV["LLMX_#{name.upcase}_BIN"]
  return override if override && File.executable?(override)

  candidates = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
                  .reject { |dir| SHIM_MARKERS.any? { |m| dir.include?(m) } }
                  .map { |dir| File.join(dir, name) }
                  .select { |p| File.executable?(p) && !File.directory?(p) }
  found = candidates.first
  abort "cannot find a real #{name} binary outside shim directories" unless found

  found
end

# --- one run ------------------------------------------------------------------

# `model: :default` means "pass no --model and let the machine choose". Every
# other condition pins the model, because a condition that changed the model
# would change the system prompt underneath the layer being measured.
def host_command(cond, workdir)
  case cond[:agent]
  when "claude"
    model_args = cond[:model] == :default ? [] : ["--model", CLAUDE_MODEL]
    [real_binary("claude"), "-p",
     "--output-format", "stream-json", "--verbose",
     *model_args,
     "--no-session-persistence",
     "--permission-mode", "bypassPermissions",
     *cond[:args]]
  when "codex"
    [real_binary("codex"), "exec", "--json",
     "--skip-git-repo-check", "--ephemeral",
     "-s", "read-only",
     "-m", CODEX_MODEL,
     "-C", workdir,
     *cond[:args], "-"]
  end
end

# The container half. Credentials are copied out of the read-only mount into a
# directory that dies with the container, so a probe cannot write into the store
# every other run reads. This mirrors what the trial runner does.
def container_script(cond)
  case cond[:agent]
  when "claude"
    <<~SH
      set -u
      mkdir -p /home/agent/.claude-trial /home/agent/probe
      for f in .credentials.json .claude.json settings.json; do
        cp "/home/agent/.agent-auth/claude/$f" /home/agent/.claude-trial/ 2>/dev/null || true
      done
      export CLAUDE_CONFIG_DIR=/home/agent/.claude-trial
      cd /home/agent/probe
      claude --version > /results/agent-version.txt 2>&1
      claude -p --output-format stream-json --verbose \
        --model #{CLAUDE_MODEL} --no-session-persistence \
        --permission-mode bypassPermissions \
        < /results/prompt.txt > /results/transcript.jsonl 2> /results/stderr.log
      echo $? > /results/exit-code.txt
    SH
  when "codex"
    <<~SH
      set -u
      mkdir -p /home/agent/.codex-trial /home/agent/probe
      cp /home/agent/.agent-auth/codex/auth.json /home/agent/.codex-trial/ 2>/dev/null || true
      export CODEX_HOME=/home/agent/.codex-trial
      cd /home/agent/probe
      codex --version > /results/agent-version.txt 2>&1
      codex exec --json --skip-git-repo-check --ephemeral --ignore-user-config \
        -s read-only -m #{CODEX_MODEL} -C /home/agent/probe \
        "$(cat /results/prompt.txt)" \
        > /results/transcript.jsonl 2> /results/stderr.log
      echo $? > /results/exit-code.txt
    SH
  end
end

def run_host(cond, outdir)
  workdir =
    case cond[:cwd]
    when :project
      abort "condition #{cond[:key]} needs LLMX_PROJECT_DIR" unless PROJECT_DIR
      PROJECT_DIR
    else
      Dir.mktmpdir("llmx-probe-")
    end

  cmd = host_command(cond, workdir)
  transcript = File.join(outdir, "transcript.jsonl")
  stderr_log = File.join(outdir, "stderr.log")

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  status = nil
  timed_out = false

  File.open(transcript, "w") do |out|
    File.open(stderr_log, "w") do |err|
      Open3.popen3(*cmd, chdir: workdir) do |stdin, stdout, stderr_io, wait|
        stdin.write(PROMPT)
        stdin.close
        readers = [Thread.new { out.write(stdout.read) }, Thread.new { err.write(stderr_io.read) }]
        unless wait.join(TIMEOUT)
          timed_out = true
          Process.kill("TERM", wait.pid) rescue nil
          wait.join
        end
        readers.each(&:join)
        status = wait.value
      end
    end
  end

  FileUtils.remove_entry(workdir) if cond[:cwd] != :project && workdir.include?("llmx-probe-")

  { "exit_code" => status&.exitstatus, "timed_out" => timed_out,
    "wall_seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2),
    "argv" => cmd.map { |a| a.sub(Dir.home, "<home>") },
    "cwd_kind" => cond[:cwd].to_s }
end

def run_container(cond, outdir)
  Kit.ensure_system_started!
  abort "base image #{Kit::BASE_IMAGE} not found; run build_base.rb" unless Kit.image_exists?(Kit::BASE_IMAGE)

  File.write(File.join(outdir, "prompt.txt"), PROMPT + "\n")
  args = ["container", "run", "--rm",
          *Kit.run_args(memory: "4g", cpus: "4"),
          "--volume", "#{outdir}:/results",
          Kit::BASE_IMAGE, "bash", "-lc", container_script(cond)]

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  out, ok = Kit.try(*args)
  File.write(File.join(outdir, "container.log"), out)

  inner = File.join(outdir, "exit-code.txt")
  { "exit_code" => File.exist?(inner) ? File.read(inner).to_i : (ok ? 0 : 1),
    "timed_out" => false,
    "wall_seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2),
    "argv" => args.map { |a| a.sub(Dir.home, "<home>") },
    "cwd_kind" => "container-empty" }
end

# --- driver -------------------------------------------------------------------

agent_filter = nil
condition_filter = nil
repeats = 1
run_all = false

argv = ARGV.dup
until argv.empty?
  case (arg = argv.shift)
  when "--agent" then agent_filter = argv.shift
  when "--condition" then condition_filter = argv.shift
  when "--repeats" then repeats = Integer(argv.shift)
  when "--all" then run_all = true
  when "--list"
    CONDITIONS.each { |c| puts format("%-8s %-16s %s", c[:agent], c[:key], c[:note]) }
    exit 0
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

selected = CONDITIONS.select do |c|
  (agent_filter.nil? || c[:agent] == agent_filter) &&
    (condition_filter.nil? || c[:key] == condition_filter)
end
abort "nothing selected; try --list" if selected.empty?
abort "pass --all, --agent or --condition" unless run_all || agent_filter || condition_filter

selected.each do |cond|
  repeats.times do |i|
    stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    outdir = File.join(RAW, cond[:agent], cond[:key], stamp)
    FileUtils.mkdir_p(outdir)

    Kit.log "#{cond[:agent]}/#{cond[:key]} run #{i + 1}/#{repeats}"
    result = cond[:where] == :container ? run_container(cond, outdir) : run_host(cond, outdir)

    meta = {
      "agent" => cond[:agent],
      "condition" => cond[:key],
      "where" => cond[:where].to_s,
      "note" => cond[:note],
      "repeat" => i + 1,
      "model_requested" => cond[:model] == :default ? "machine default" : (cond[:agent] == "claude" ? CLAUDE_MODEL : CODEX_MODEL),
      "recorded_at" => Time.now.utc.iso8601,
      "project_label" => cond[:cwd] == :project ? File.basename(PROJECT_DIR.to_s) : nil
    }.merge(result)

    File.write(File.join(outdir, "meta.json"), JSON.pretty_generate(meta))
    Kit.log "  exit=#{result['exit_code']} #{result['wall_seconds']}s -> #{outdir.sub(EXPERIMENT_DIR + '/', '')}"
  end
end
