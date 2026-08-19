#!/usr/bin/env ruby
# frozen_string_literal: true

# Opens a trial container with an interactive agent TUI, for running a condition
# by hand and reading the session back afterwards.
#
#   ruby at-file-mentions/scripts/manual_trial.rb --bug campfire-01 --agent claude --condition at_noline
#   ruby at-file-mentions/scripts/manual_trial.rb --bug campfire-01 --agent codex  --condition at_noline
#
# Why this exists: `claude -p` and the TUI are different front ends, and @ is a
# feature of the input box. A headless result does not settle what the
# interactive client does, so this runs the same prompt through the same
# container with a human at the keyboard.
#
# The difference from an automated trial is the config directory. Automated
# trials get a private one that dies with the container, so no state can cross
# between them. Here the config directory is bind-mounted from the host, because
# the whole point is to read the session file the TUI writes. That makes this
# NOT hermetic in the way a scored trial is - it is an observation, not a trial,
# and its output lands in results-manual/ rather than results-raw/.
#
# The container still starts from the same image on the same planted branch, so
# what the agent sees is identical.

require "base64"
require "fileutils"
require "json"
require_relative "../../containers/scripts/lib/kit"

AGENTS = %w[claude codex].freeze

bug_id = nil
agent = "claude"
condition = "at_noline"
# How the mention reaches the input box. Pasting and typing are different code
# paths: typing `@` opens a file picker and selecting from it is the client's
# own attach flow, while a paste is just text the client may or may not parse
# for mentions. A client can implement one and not the other, so which was used
# has to travel with the result.
entry = "paste"

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--bug" then bug_id = args.shift
  when "--agent" then agent = args.shift
  when "--condition" then condition = args.shift
  when "--entry" then entry = args.shift
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

abort "--bug is required" unless bug_id
abort "--agent must be one of #{AGENTS.join(', ')}" unless AGENTS.include?(agent)
abort "--entry must be paste or typed" unless %w[paste typed].include?(entry)

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

stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
out_dir = File.join(EXPERIMENT_DIR, "results-manual", bug_id, agent, "#{condition}-#{entry}", stamp)
config_dir = File.join(out_dir, "config")
FileUtils.mkdir_p(config_dir)
File.write(File.join(out_dir, "prompt.txt"), prompt)

# Seed the config directory with credentials only, the same files runner.rb
# copies. Everything the session writes then lands beside them, on the host.
seed = File.join(Kit::AUTH_DIR, agent)
%w[.credentials.json .claude.json settings.json auth.json config.toml].each do |f|
  from = File.join(seed, f)
  FileUtils.cp(from, File.join(config_dir, f)) if File.exist?(from)
end

File.write(File.join(out_dir, "meta.json"), JSON.pretty_generate(
                                              "bug_id" => bug_id, "app" => app["key"], "agent" => agent,
                                              "condition" => condition, "branch" => "trial/#{bug_id}", "entry" => entry,
                                              "mode" => "manual-tui", "started_at" => stamp
                                            ))

env = {
  "LLMX_PROMPT_B64" => Base64.strict_encode64(prompt),
  agent == "claude" ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME" => "/home/agent/.agent-config"
}

setup = +<<~SH
  set -e
  cd /workspace/app
  git checkout -q trial/#{bug_id}
  git branch --format='%(refname:short)' | grep -v '^trial/#{bug_id}$' | xargs -r -n1 git branch -q -D
  git reflog expire --expire=now --all >/dev/null 2>&1 || true
  git gc --prune=now --quiet >/dev/null 2>&1 || true
SH

if app["database"] == "postgresql"
  setup << <<~SH
    PGBIN=$(dirname $(ls /usr/lib/postgresql/*/bin/pg_ctl | head -1))
    $PGBIN/pg_ctl -D "${PGDATA:-/home/agent/pgdata}" -l /tmp/postgres.log -o "-p 5432" -w start >/dev/null 2>&1 || true
  SH
end

setup << <<~SH
  #{app['db_prepare']} >/dev/null 2>&1 || true
  echo "$LLMX_PROMPT_B64" | base64 -d > /home/agent/prompt.txt
  clear
  cat <<'BANNER'
  ================================================================
   MANUAL TRIAL  #{bug_id} / #{agent} / #{condition}
   entry mode: #{entry}
  ================================================================

   Start the TUI:   #{agent}

#{if entry == 'typed'
    <<~TYPED
       ENTRY MODE "typed" - do NOT paste the whole prompt.

       Type the prompt, and where a path appears, type `@` and pick the
       file from the client's own completion list rather than typing the
       path out. Selecting from that list is the client's attach flow,
       and it is a different code path from pasted text.

       The two paths to tag:
         #{bug['hint_paths'].join("\n         ")}
    TYPED
  else
    <<~PASTE
       ENTRY MODE "paste" - paste the prompt below verbatim.

       Check what actually arrived in the input box before sending: a
       previous run lost the second `@` somewhere between clipboard and
       TUI, which would have been mistaken for the client ignoring it.
    PASTE
  end}
   The prompt is also at /home/agent/prompt.txt.
   When the agent is done, type `exit` to close the container.
  ================================================================

BANNER
  cat /home/agent/prompt.txt
  echo
  echo "----------------------------------------------------------------"
  echo
  exec bash
SH

cmd = ["container", "run", "--rm", "--interactive", "--tty",
       *Kit.run_args(mount_auth: false),
       "--volume", "#{File.expand_path(config_dir)}:/home/agent/.agent-config",
       "--workdir", "/workspace/app"]
env.each { |k, v| cmd += ["--env", "#{k}=#{v}"] }
cmd += [image, "bash", "-lc", setup]

Kit.log "manual trial #{bug_id} / #{agent} / #{condition}"
Kit.log "config and session will persist in #{config_dir}"
puts
system(*cmd)

puts
Kit.log "session files written to the host:"
pattern = agent == "claude" ? "**/projects/**/*.jsonl" : "**/sessions/**/*.jsonl"
found = Dir.glob(File.join(config_dir, pattern))
if found.empty?
  Kit.log "  none found - did the TUI actually run? looked for #{pattern}"
else
  found.each { |f| puts format("  %s  (%d lines)", f.sub(EXPERIMENT_DIR + "/", ""), File.readlines(f).size) }
  puts
  Kit.log "read it with: ruby at-file-mentions/scripts/parse_manual.rb #{out_dir.sub(EXPERIMENT_DIR + '/', '')}"
end
