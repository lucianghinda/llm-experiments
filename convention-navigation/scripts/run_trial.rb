#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs one trial: one task, one agent, one condition, in a fresh container.
#
#   ruby convention-navigation/scripts/run_trial.rb --task locate-direct-type \
#        --agent claude --condition conventional
#   ruby convention-navigation/scripts/run_trial.rb --task locate-direct-type \
#        --agent claude --condition scrambled --dry-run
#
# The trial runs to completion under a wall-clock timeout rather than being
# killed at the first edit. Stopping early would measure the cost of finding the
# place and throw away whether the change was any good, and an analysis cap can
# always be applied afterwards from the event log, whereas a killed trial cannot
# be un-killed.
#
# Results land in results-raw/ (gitignored). Nothing reaches results/ until
# sanitize.rb has looked at it.

require "base64"
require "fileutils"
require "json"
require_relative "../../containers/scripts/lib/kit"

AGENTS = %w[claude codex].freeze

# Which branch in the image each condition runs against, which layout that
# branch holds, and which map file -- if any -- runner.rb writes at trial time,
# named for the agent that will read it.
#
# Each layout gets its own map, describing that layout truthfully. Handing the
# conventional tree the scrambled tree's map would be a fourth experiment, about
# what a wrong map costs, and would say nothing about what a right one buys.
#
# `conventional-mapped` exists to answer the one question `scrambled-mapped`
# raised and could not settle: the mapped arm came in under conventional, but
# only the mapped arm carried an agent-instruction file at all, so the gain
# could have been the map or could have been the mere presence of a document.
# Holding the document constant and varying only what it has to tell you is what
# separates them.
CONDITIONS = {
  "conventional" => { branch: "trial/v1", variant: "conventional", map: nil },
  "scrambled" => { branch: "trial/v2", variant: "scrambled", map: nil },
  "scrambled-mapped" => { branch: "trial/v2", variant: "scrambled", map: "map.md" },
  "conventional-mapped" => { branch: "trial/v1", variant: "conventional", map: "map-conventional.md" }
}.freeze

# Pinned so a result can be attributed to a model. Recorded in meta either way:
# for Claude the transcript's init event reports what actually answered.
MODELS = {
  "claude" => ENV.fetch("LLMX_CLAUDE_MODEL", "claude-opus-5"),
  "codex" => ENV.fetch("LLMX_CODEX_MODEL", "gpt-5.6-sol")
}.freeze

task_id = nil
agent = nil
condition = nil
dry_run = false
timeout_override = nil

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--task" then task_id = args.shift
  when "--agent" then agent = args.shift
  when "--condition" then condition = args.shift
  when "--timeout" then timeout_override = args.shift.to_i
  when "--dry-run" then dry_run = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

abort "--task is required" unless task_id
abort "--agent must be one of #{AGENTS.join(', ')}" unless AGENTS.include?(agent)
abort "--condition must be one of #{CONDITIONS.keys.join(', ')}" unless CONDITIONS.key?(condition)

EXPERIMENT_DIR = File.expand_path("..", __dir__)
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
tasks = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "tasks.yml"))["tasks"]

task = tasks.find { |t| t["id"] == task_id } or abort "unknown task: #{task_id}"
app = apps.find { |a| a["key"] == task["app"] } or abort "tasks.yml references unknown app"
setup = CONDITIONS[condition]

prompt_path = File.join(EXPERIMENT_DIR, "prompts", app["key"], "#{task_id}.txt")
abort "missing #{prompt_path}; run render_prompts.rb" unless File.exist?(prompt_path)
prompt = File.read(prompt_path)

# The targets are ground truth for tool_calls_to_first_target_read and differ
# between layouts, because the same file has two paths.
targets = Array(task["targets_#{setup[:variant]}"])
abort "tasks.yml gives #{task_id} no targets_#{setup[:variant]}" if targets.empty?

image = "llmx-conv-#{app['key']}:latest"
Kit.ensure_system_started!
unless Kit.image_exists?(image)
  abort "image #{image} not found; run build_variant_image.rb --app #{app['key']}"
end

# Preflight the login rather than discovering it is dead halfway through a grid.
#
# `claude auth status` reports loggedIn: true for a credential whose access
# token expired hours ago, because being logged in and being able to make a
# request are different questions. So the expiry is read directly first. Only
# the refresh token matters: an expired access token is refreshed in flight, but
# an expired refresh token can only be replaced by logging in again, and every
# trial from that point on dies without producing data.
if agent == "claude"
  cred = File.join(Kit::AUTH_DIR, "claude", ".credentials.json")
  if File.exist?(cred)
    oauth = begin
      JSON.parse(File.read(cred)).values.first || {}
    rescue StandardError
      {}
    end
    expires = oauth["refreshTokenExpiresAt"].to_i
    now_ms = (Time.now.to_f * 1000).to_i

    dead =
      if oauth["refreshToken"].to_s.empty?
        # A failed authentication does not leave the file alone: the CLI rewrites
        # it with the same keys and empty values. `claude auth status` still
        # answers loggedIn: true for that, so the shape has to be checked here.
        "the stored refresh token is empty (a previous run failed to authenticate)"
      elsif expires.positive? && expires < now_ms
        "the stored refresh token expired at #{Time.at(expires / 1000).utc}"
      end

    if dead
      abort <<~MSG
        Refusing to start: #{dead}.
        Trials would run, cost container time, and produce no data.

        Log in again, once:
          ruby containers/scripts/auth_setup.rb --agent claude
      MSG
    end
  end
end

check = agent == "claude" ? "claude auth status 2>&1" : "codex login status 2>&1"
status, = dry_run ? ["", true] : Kit.try("container", "run", "--rm", *Kit.run_args,
                                         Kit::BASE_IMAGE, "bash", "-lc", check)
if status.include?('"loggedIn": false') || status.include?("Not logged in")
  abort <<~MSG
    #{agent} is not logged in inside the container, so this trial would fail.

    Run this once and complete the browser flow:
      ruby containers/scripts/auth_setup.rb --agent #{agent}

    Credentials persist in #{Kit::AUTH_DIR} and are mounted into every trial.
  MSG
end

stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
out_dir = File.join(EXPERIMENT_DIR, "results-raw", task_id, agent, condition, stamp)

check_source = task["check"] && File.join(EXPERIMENT_DIR, "checks", app["key"], task["check"])
if check_source && !File.exist?(check_source)
  abort "missing acceptance check #{check_source}"
end

# Nothing is written until the trial is real. A dry run that laid down a results
# directory would leave a cell that run_grid.rb counts as already done, so
# inspecting the plan would silently remove work from it.
unless dry_run
  FileUtils.mkdir_p(File.join(out_dir, "checks", "lib"))
  FileUtils.mkdir_p(File.join(out_dir, "checks", "task"))

  # The runner and the acceptance check are copied in rather than baked into the
  # image, so fixing either does not mean rebuilding a multi-gigabyte app image.
  FileUtils.cp(File.join(__dir__, "runner.rb"), File.join(out_dir, "runner.rb"))
  # checks/task/ + checks/lib/ reproduces the directory shape the checks have in
  # the repository, where each one lives in checks/<app>/ and reaches its helper
  # through `require_relative "../lib/acceptance"`. Copying the check one level
  # flatter breaks that require, and it breaks it inside the container after the
  # agent has already run, so the trial is spent before the error appears.
  FileUtils.cp(File.join(EXPERIMENT_DIR, "checks", "lib", "acceptance.rb"),
               File.join(out_dir, "checks", "lib", "acceptance.rb"))
  FileUtils.cp(check_source, File.join(out_dir, "checks", "task", task["check"])) if check_source
  File.write(File.join(out_dir, "prompt.txt"), prompt)
end

env = {
  "LLMX_TASK" => task_id,
  "LLMX_APP" => app["key"],
  "LLMX_AGENT" => agent,
  "LLMX_CONDITION" => condition,
  "LLMX_VARIANT" => setup[:variant],
  "LLMX_BRANCH" => setup[:branch],
  "LLMX_TARGETS" => targets.join(","),
  "LLMX_CHECK_FILE" => task["check"].to_s,
  "LLMX_DB_PREPARE" => app["db_prepare"],
  "LLMX_DATABASE" => app["database"],
  "LLMX_TIMEOUT_SECONDS" => (timeout_override || task["timeout_seconds"] || 900).to_s,
  "LLMX_REGRESSION_SUITE" => ENV.fetch("LLMX_REGRESSION_SUITE", "1"),
  # Base64 keeps the prompt out of shell quoting entirely: newlines, backticks
  # and quotes in a prompt must not become shell syntax.
  "LLMX_PROMPT_B64" => Base64.strict_encode64(prompt)
}
env["LLMX_MODEL"] = MODELS[agent] if MODELS[agent]

if setup[:map]
  map_path = File.join(EXPERIMENT_DIR, "variants", app["key"], setup[:map])
  abort "missing #{map_path}, which is the whole of the mapped condition" unless File.exist?(map_path)

  env["LLMX_MAP_B64"] = Base64.strict_encode64(File.read(map_path))
end

cmd = ["container", "run", "--rm",
       *Kit.run_args,
       "--volume", "#{out_dir}:/results",
       "--workdir", "/workspace/app"]
env.each { |k, v| cmd += ["--env", "#{k}=#{v}"] }
# Through a login shell, not `ruby` directly. Apple's `container run` does not
# apply the image's ENV PATH when it resolves the command binary, and the rubies
# are mise shims, so a direct exec fails with a bare "No such file or directory"
# that reads like a missing runner.rb rather than a missing interpreter.
cmd += [image, "bash", "-lc", "exec ruby /results/runner.rb"]

if dry_run
  # Redacted, not removed. Dropping the value left its `--env` flag behind and
  # printed a command that would not run, which is a confusing thing for a
  # dry run to show.
  shown = cmd.map { |c| c.sub(/\A(LLMX_(?:PROMPT|MAP)_B64)=.*\z/m, '\1=<base64, elided>') }
  puts "would run:"
  puts "  #{shown.shelljoin}"
  puts "\ntargets (#{setup[:variant]}): #{targets.join(', ')}"
  puts "\nprompt:\n\n#{prompt}"
  exit 0
end

puts "trial #{task_id} / #{agent} / #{condition} -> #{out_dir}"
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ok = system(*cmd)
elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)

meta_path = File.join(out_dir, "meta.json")
unless File.exist?(meta_path)
  abort "\ntrial produced no meta.json after #{elapsed}s (container exit #{ok.inspect}). " \
        "Inspect #{out_dir}."
end

meta = JSON.parse(File.read(meta_path))
meta["host_wall_seconds"] = elapsed
meta["container_ok"] = ok
# Which source map this trial carried. runner.rb records the name it wrote
# inside the container (CLAUDE.md or AGENTS.md), which says who read it but not
# which of the two layouts it describes -- and once two mapped conditions exist,
# that is the part a reader needs.
meta["map_source"] = setup[:map] if setup[:map]
File.write(meta_path, JSON.pretty_generate(meta))

# A cell that died before the agent got a turn is not a result. Exiting non-zero
# is what stops run_grid.rb from treating it as done, so the cell is retried
# instead of silently entering the data as a failure.
if meta["aborted"]
  warn "\n#{task_id} / #{agent} / #{condition}: ABORTED (#{meta['aborted']}" \
       "#{meta['api_error_reason'] ? ": #{meta['api_error_reason']}" : ''}) after #{elapsed}s"
  warn "This cell produced no usable data and should be run again."
  exit 2
end

puts format("\n  clean tree before : %s", meta["clean_tree_before"])
puts format("  agent exit        : %s (timed out: %s)", meta["agent_exit"], meta["timed_out"])
puts format("  changed files     : %s", meta["changed_files"].inspect)
puts format("  passed            : %s", meta["passed"].inspect)
puts format("  wall seconds      : %s (agent), %s (host)", meta["wall_seconds"], elapsed)
puts "\nparse with: ruby convention-navigation/scripts/parse_transcript.rb #{out_dir}"
