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

# Every model is pinned. A condition that changed the model would change the
# system prompt underneath the thing being measured, and the conditions that move
# a config directory would otherwise be free to fall back to a different default.
#
# Codex and opencode are pinned to the same model on purpose. They are the only
# pair here that can be compared directly, because whatever differs between them
# is the harness rather than the model.
CLAUDE_MODEL = ENV.fetch("LLMX_CLAUDE_MODEL", "sonnet")
CODEX_MODEL = ENV.fetch("LLMX_CODEX_MODEL", "gpt-5.6-sol")
OPENCODE_MODEL = ENV.fetch("LLMX_OPENCODE_MODEL", "openai/gpt-5.6-sol")

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
  when "opencode"
    # opencode takes the prompt as an argument rather than on stdin, and has no
    # flag for "do not save this session"; see private_opencode_data.
    [real_binary("opencode"), "run", "--format", "json",
     "-m", OPENCODE_MODEL,
     *cond[:args], PROMPT]
  end
end

# opencode keeps credentials, sessions and its database together under
# XDG_DATA_HOME, and offers no --ephemeral. Pointing that variable at a fresh
# directory holding only the credential file is the closest equivalent: the run
# cannot read state from an earlier run and cannot leave any behind.
#
# The seed is the kit's credential store, the same file the container reads, so
# host and container start from identical credentials.
def private_opencode_data
  dir = Dir.mktmpdir("llmx-opencode-data-")
  FileUtils.mkdir_p(File.join(dir, "opencode"))
  seed = File.join(Kit::AUTH_DIR, "opencode", "auth.json")
  abort "no opencode credentials; run containers/scripts/seed_opencode_auth.rb" unless File.exist?(seed)

  FileUtils.cp(seed, File.join(dir, "opencode", "auth.json"))
  dir
end

# opencode has no --strict-mcp-config: its servers are declared in opencode.json
# and there is no way to suppress them for one run. Removing only that layer
# therefore means rebuilding the config directory: the JSON is written out again
# without its "mcp" key and every other entry is symlinked to the real one, so
# the only difference between this and host-full is the MCP servers.
def opencode_config_without_mcp
  source = File.join(Dir.home, ".config", "opencode")
  abort "no opencode config at #{source}" unless Dir.exist?(source)

  root = Dir.mktmpdir("llmx-opencode-config-")
  target = File.join(root, "opencode")
  FileUtils.mkdir_p(target)

  Dir.children(source).each do |entry|
    next if entry == "opencode.json"

    FileUtils.ln_s(File.join(source, entry), File.join(target, entry))
  end

  settings = JSON.parse(File.read(File.join(source, "opencode.json")))
  settings.delete("mcp")
  File.write(File.join(target, "opencode.json"), JSON.pretty_generate(settings))
  root
end

# Conditions may set environment variables. The symbols are recipes rather than
# values, because what a condition needs is a directory built a particular way
# and the path it lands on changes every run. Anything created here is appended
# to `scratch` so the caller removes it when the run is over.
def condition_env(cond, scratch)
  env = {}
  (cond[:env] || {}).each do |key, value|
    env[key] =
      case value
      when :empty_dir
        Dir.mktmpdir("llmx-empty-").tap { |dir| scratch << dir }
      when :opencode_config_without_mcp
        opencode_config_without_mcp.tap { |dir| scratch << dir }
      else
        value.to_s
      end
  end
  env
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
  when "opencode"
    # XDG_CONFIG_HOME is pointed at an empty directory as well as XDG_DATA_HOME.
    # The image has no opencode config in it, but saying so explicitly means the
    # container floor does not depend on that staying true.
    <<~SH
      set -u
      mkdir -p /home/agent/.opencode-data/opencode /home/agent/.opencode-config /home/agent/probe
      cp /home/agent/.agent-auth/opencode/auth.json /home/agent/.opencode-data/opencode/ 2>/dev/null || true
      export XDG_DATA_HOME=/home/agent/.opencode-data
      export XDG_CONFIG_HOME=/home/agent/.opencode-config
      cd /home/agent/probe
      opencode --version > /results/agent-version.txt 2>&1
      opencode run --format json -m #{OPENCODE_MODEL} \
        "$(cat /results/prompt.txt)" \
        > /results/transcript.jsonl 2> /results/stderr.log
      echo $? > /results/exit-code.txt
    SH
  end
end

def run_host(cond, outdir)
  # Every scratch directory made for this run, removed together at the end. They
  # have to outlive the command and not outlive the run.
  scratch = []
  make_scratch = ->(prefix) { Dir.mktmpdir(prefix).tap { |d| scratch << d } }

  workdir =
    case cond[:cwd]
    when :project
      abort "condition #{cond[:key]} needs LLMX_PROJECT_DIR" unless PROJECT_DIR
      PROJECT_DIR
    else
      make_scratch.call("llmx-probe-")
    end

  env = condition_env(cond, scratch)
  if cond[:agent] == "opencode"
    data = private_opencode_data
    scratch << data
    env["XDG_DATA_HOME"] = data
  end

  cmd = host_command(cond, workdir)
  transcript = File.join(outdir, "transcript.jsonl")
  stderr_log = File.join(outdir, "stderr.log")

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  status = nil
  timed_out = false

  File.open(transcript, "w") do |out|
    File.open(stderr_log, "w") do |err|
      Open3.popen3(env, *cmd, chdir: workdir) do |stdin, stdout, stderr_io, wait|
        # Claude and Codex read the prompt from stdin. opencode takes it as an
        # argument, and handing it the prompt twice would measure a different
        # message than the other two got.
        stdin.write(PROMPT) unless cond[:agent] == "opencode"
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

  scratch.each { |dir| FileUtils.remove_entry(dir, true) }

  { "exit_code" => status&.exitstatus, "timed_out" => timed_out,
    "wall_seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2),
    "argv" => cmd.map { |a| a.sub(Dir.home, "<home>") },
    # Which variables the condition set, without their values: a value here is a
    # scratch path that changes every run and means nothing to a later reader.
    "env_overrides" => env.keys.sort,
    "cwd_kind" => cond[:cwd].to_s }
end

def run_container(cond, outdir)
  Kit.ensure_system_started!

  # opencode is not in the base image; it lives one layer above it. See
  # containers/opencode/Containerfile for why, and note that this means the
  # opencode floor and the other two floors are not byte-identical environments:
  # the opencode image is the base image plus one npm package.
  image = cond[:agent] == "opencode" ? Kit::OPENCODE_IMAGE : Kit::BASE_IMAGE
  unless Kit.image_exists?(image)
    builder = cond[:agent] == "opencode" ? "build_opencode_image.rb" : "build_base.rb"
    abort "image #{image} not found; run containers/scripts/#{builder}"
  end

  File.write(File.join(outdir, "prompt.txt"), PROMPT + "\n")
  args = ["container", "run", "--rm",
          *Kit.run_args(memory: "4g", cpus: "4"),
          "--volume", "#{outdir}:/results",
          image, "bash", "-lc", container_script(cond)]

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


def model_label(cond)
  return "machine default" if cond[:model] == :default

  { "claude" => CLAUDE_MODEL, "codex" => CODEX_MODEL, "opencode" => OPENCODE_MODEL }.fetch(cond[:agent])
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
      "model_requested" => model_label(cond),
      "recorded_at" => Time.now.utc.iso8601,
      "project_label" => cond[:cwd] == :project ? File.basename(PROJECT_DIR.to_s) : nil
    }.merge(result)

    File.write(File.join(outdir, "meta.json"), JSON.pretty_generate(meta))
    Kit.log "  exit=#{result['exit_code']} #{result['wall_seconds']}s -> #{outdir.sub(EXPERIMENT_DIR + '/', '')}"
  end
end
