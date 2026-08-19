#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs one trial: one bug, one agent, one condition, in a fresh container.
#
#   ruby at-file-mentions/scripts/run_trial.rb --bug campfire-01 --agent claude --condition at
#   ruby at-file-mentions/scripts/run_trial.rb --bug campfire-01 --agent claude --condition at --dry-run
#
# On caps: the trial runs to completion under a wall-clock timeout rather than
# being killed at the first edit. Stopping at the first edit would measure the
# cost of locating the defect but throw away whether the fix was any good, and
# an analysis cap can always be applied afterwards from the event log, whereas a
# killed trial cannot be un-killed. parse_transcript.rb reports both the index of
# the first defect-file read and the index of the first edit, so a "cost to
# locate" figure is still available without destroying anything.
#
# Results land in results-raw/ (gitignored). Nothing reaches results/ until
# sanitize.rb has looked at it.

require "base64"
require "fileutils"
require "json"
require_relative "../../containers/scripts/lib/kit"

AGENTS = %w[claude codex].freeze
CONDITIONS = %w[none bare at bare_noline at_noline].freeze

# Pinned so a result can be attributed to a model. Recorded in meta either way:
# the transcript's init event reports what actually answered.
#
# The Codex default was left unset for the first 30 trials, so those results
# cannot be attributed to a version: `codex exec` writes no model field to its
# transcript, and meta recorded model_requested: null. The id below is the one
# the TUI session files show this CLI actually resolving to, read back from
# results-manual/.../sessions/rollout-*.jsonl rather than guessed. Because the
# earlier runs are unattributable they must not be pooled with new ones.
MODELS = {
  "claude" => ENV.fetch("LLMX_CLAUDE_MODEL", "claude-opus-5"),
  "codex" => ENV.fetch("LLMX_CODEX_MODEL", "gpt-5.6-sol")
}.freeze

bug_id = nil
agent = nil
condition = nil
dry_run = false
timeout_s = ENV.fetch("LLMX_TRIAL_TIMEOUT", "900").to_i

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--bug" then bug_id = args.shift
  when "--agent" then agent = args.shift
  when "--condition" then condition = args.shift
  when "--timeout" then timeout_s = args.shift.to_i
  when "--dry-run" then dry_run = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

abort "--bug is required" unless bug_id
abort "--agent must be one of #{AGENTS.join(', ')}" unless AGENTS.include?(agent)
abort "--condition must be one of #{CONDITIONS.join(', ')}" unless CONDITIONS.include?(condition)

EXPERIMENT_DIR = File.expand_path("..", __dir__)
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]

bug = bugs.find { |b| b["id"] == bug_id } or abort "unknown bug: #{bug_id}"
app = apps.find { |a| a["key"] == bug["app"] } or abort "bugs.yml references unknown app"

prompt_path = File.join(EXPERIMENT_DIR, "prompts", app["key"], bug_id, "#{condition}.txt")
abort "missing #{prompt_path}; run render_prompts.rb" unless File.exist?(prompt_path)
prompt = File.read(prompt_path)

image = "llmx-app-#{app['key']}:latest"
Kit.ensure_system_started!
abort "image #{image} not found; run build_app_image.rb --app #{app['key']}" unless Kit.image_exists?(image)

# Preflight the login rather than discovering it is dead halfway through a grid.
# `claude auth status` reports JSON with loggedIn; `codex login status` prints
# "Not logged in". Both read the mounted credentials directory, so this asks the
# same question a trial would.
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
out_dir = File.join(EXPERIMENT_DIR, "results-raw", bug_id, agent, condition, stamp)
FileUtils.mkdir_p(out_dir)

# The runner is copied in rather than baked into the image, so fixing the
# harness does not mean rebuilding three app images.
FileUtils.cp(File.join(__dir__, "runner.rb"), File.join(out_dir, "runner.rb"))
File.write(File.join(out_dir, "prompt.txt"), prompt)

env = {
  "LLMX_BUG_ID" => bug_id,
  "LLMX_APP" => app["key"],
  "LLMX_AGENT" => agent,
  "LLMX_CONDITION" => condition,
  "LLMX_BRANCH" => "trial/#{bug_id}",
  "LLMX_TEST_FILE" => bug["test_file"],
  "LLMX_IMPL_FILES" => Array(bug["impl_files"]).join(","),
  "LLMX_DB_PREPARE" => app["db_prepare"],
  "LLMX_DATABASE" => app["database"],
  "LLMX_TIMEOUT_SECONDS" => timeout_s.to_s,
  # Base64 keeps the prompt out of shell quoting entirely: newlines, backticks
  # and quotes in a prompt must not become shell syntax.
  "LLMX_PROMPT_B64" => Base64.strict_encode64(prompt)
}
model = MODELS[agent]
env["LLMX_MODEL"] = model if model

cmd = ["container", "run", "--rm",
       *Kit.run_args,
       "--volume", "#{out_dir}:/results",
       "--workdir", "/workspace/app"]
env.each { |k, v| cmd += ["--env", "#{k}=#{v}"] }
# Through a login shell, not `ruby` directly. Apple's `container run` does not
# apply the image's ENV PATH when it resolves the command binary, and the rubies
# are mise shims under /opt/mise/shims, so a direct exec fails with a bare
# "No such file or directory" that reads like a missing runner.rb rather than a
# missing interpreter. The login shell also gives the runner the PATH it needs to
# find `claude` and `codex` later. `exec` so the runner's exit status is the
# container's, not bash's.
cmd += [image, "bash", "-lc", "exec ruby /results/runner.rb"]

if dry_run
  puts "would run:"
  puts "  #{cmd.reject { |c| c.start_with?('LLMX_PROMPT_B64') }.join(' ')}"
  puts "\nprompt (#{condition}):\n\n#{prompt}"
  exit 0
end

puts "trial #{bug_id} / #{agent} / #{condition} -> #{out_dir}"
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ok = system(*cmd)
elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)

meta_path = File.join(out_dir, "meta.json")
unless File.exist?(meta_path)
  abort "\ntrial produced no meta.json after #{elapsed}s (container exit #{ok.inspect}). " \
        "Inspect #{out_dir}, or open a shell with containers/scripts/trial_shell.rb --app #{app['key']}"
end

meta = JSON.parse(File.read(meta_path))
meta["host_wall_seconds"] = elapsed
meta["container_ok"] = ok
File.write(meta_path, JSON.pretty_generate(meta))

puts format("\n  reproduced before : %s", meta["bug_reproduces"])
puts format("  agent exit        : %s (timed out: %s)", meta["agent_exit"], meta["timed_out"])
puts format("  changed files     : %s", meta["changed_files"].inspect)
puts format("  touched defect    : %s", meta["touched_impl_file"])
puts format("  fix verified      : %s", meta["fix_verified"])
puts format("  wall seconds      : %s (container), %s (host)", meta["wall_seconds"], elapsed)
puts "\nparse with: ruby at-file-mentions/scripts/parse_transcript.rb #{out_dir}"
