#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs inside the trial container. run_trial.rb copies this in and starts it;
# it is never executed on the host.
#
# Order matters. Everything that could tell the agent which layout it is looking
# at, or that a second layout exists at all, has to be gone before the agent
# starts.

require "base64"
require "json"
require "open3"
require "fileutils"

APP_DIR = "/workspace/app"
RESULTS = "/results"

def cfg(key, default = nil)
  value = ENV["LLMX_#{key.to_s.upcase}"]
  value.nil? || value.empty? ? default : value
end

def run(cmd, dir: APP_DIR, timeout: nil, env: {})
  cmd = "timeout #{timeout} #{cmd}" if timeout
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  out, err, status = Open3.capture3(env, cmd, chdir: dir)
  { "cmd" => cmd, "exit" => status.exitstatus, "stdout" => out, "stderr" => err,
    "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3) }
end

def log(msg)
  warn "[runner] #{msg}"
end

task_id     = cfg(:task)      or abort "LLMX_TASK required"
agent       = cfg(:agent)     or abort "LLMX_AGENT required"
condition   = cfg(:condition) or abort "LLMX_CONDITION required"
branch      = cfg(:branch)    or abort "LLMX_BRANCH required"
prompt_b64  = cfg(:prompt_b64) or abort "LLMX_PROMPT_B64 required"
variant     = cfg(:variant, "conventional")
targets     = (cfg(:targets) || "").split(",")
model       = cfg(:model)
db_prepare  = cfg(:db_prepare, "bin/rails db:test:prepare")
timeout_s   = cfg(:timeout_seconds, "900").to_i
database    = cfg(:database, "sqlite3")
check_file  = cfg(:check_file)
map_b64     = cfg(:map_b64)

prompt = Base64.strict_decode64(prompt_b64)

meta = {
  "task" => task_id,
  # Recorded, not merely passed in. sanitize.rb decides whether a trial's raw
  # transcript may be committed by looking up the app's privacy setting, and a
  # missing key resolves to "not a public app" -- which fails safe for privacy
  # but silently withholds the transcripts of an MIT-licensed app that were
  # supposed to be published.
  "app" => cfg(:app),
  "agent" => agent, "condition" => condition, "variant" => variant,
  "model_requested" => model,
  # Persisted because parse_transcript.rb needs them to compute
  # tool_calls_to_first_target_read. Without them it matches against an empty
  # list and the metric comes out nil on every row while looking like a null
  # observation rather than a broken one. at-file-mentions lost a whole grid's
  # worth of that metric to exactly this.
  "targets" => targets,
  "started_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
}

if database == "postgresql"
  log "starting postgres"
  pgbin = File.dirname(Dir.glob("/usr/lib/postgresql/*/bin/pg_ctl").first)
  pgdata = ENV.fetch("PGDATA", "/home/agent/pgdata")
  system("#{pgbin}/pg_ctl -D #{pgdata} -l /tmp/postgres.log -o '-p 5432' -w start > /dev/null 2>&1")
  ready = false
  30.times { break if (ready = system("#{pgbin}/pg_isready -q -h 127.0.0.1 -p 5432")); sleep 0.5 }
  meta["postgres_ready"] = ready
end

# --- isolate the variant ------------------------------------------------------
#
# The image ships both layouts. Two things have to go before the agent runs.
#
# The other branch, because `git diff trial/v1 trial/v2` is a complete map of
# the scramble -- and worse, it is proof that the layout was rearranged on
# purpose, which is a fact about the experiment and not about the codebase.
#
# The branch name, because `trial/v2` paired with a missing `trial/v1` still
# says a variant exists. Whichever branch survives is renamed to `main`, so
# every trial in every condition reports the same ordinary name.
log "isolating #{branch}"
run("git checkout -q #{branch}")
run("git branch --format=%(refname:short)")["stdout"].split("\n").map(&:strip)
   .reject { |b| b.empty? || b == branch }
   .each { |b| run("git branch -q -D #{b}") }
run("git branch -q -m main")

# --- the map file, for the mapped condition -----------------------------------
#
# Written here rather than committed to a third branch, and named for the agent
# reading it: Claude Code reads CLAUDE.md, Codex reads AGENTS.md. Shipping both
# to both would make one agent pay for the file twice, and this experiment
# charges the map's tokens on purpose -- a map that is not counted is not being
# compared fairly against no map.
if map_b64
  map_name = agent == "claude" ? "CLAUDE.md" : "AGENTS.md"
  File.write(File.join(APP_DIR, map_name), Base64.strict_decode64(map_b64))
  # Committed so the working tree is clean before the agent starts. An untracked
  # file would show up in the agent's own `git status` and in its diff.
  run("git add -A")
  run("git commit -q --amend --no-edit")
  meta["map_file"] = map_name
  meta["map_bytes"] = Base64.strict_decode64(map_b64).bytesize
end

meta["history_visible_to_agent"] = run("git log --all --oneline")["stdout"].strip
meta["branches_visible_to_agent"] = run("git branch --format=%(refname:short)")["stdout"]
                                    .split("\n").map(&:strip)
dirty = run("git status --porcelain")["stdout"].strip
meta["clean_tree_before"] = dirty.empty?
log "tree clean before agent: #{dirty.empty?}"

prep = run(db_prepare, timeout: 600)
meta["db_prepare_exit"] = prep["exit"]
File.write(File.join(RESULTS, "db_prepare.txt"), prep["stdout"] + prep["stderr"])

# --- a private config directory ----------------------------------------------
#
# CLAUDE_CONFIG_DIR points at the mounted credential store, and Claude Code
# derives its project state and auto-memory directory from it. That directory is
# writable, shared by every trial and persisted on the host, which would let one
# trial leave a note about where things live for the next one to read. In this
# experiment that note is the entire dependent variable.
SEEDED = %w[.credentials.json .claude.json settings.json auth.json config.toml].freeze

# The one thing that must survive a trial. Everything else in the private copy
# is deliberately thrown away; these are not, because an OAuth access token
# expires and the CLI refreshes it mid-run.
#
# Refreshing writes the new token into the private copy, which dies with the
# container, so the shared store keeps the old one. If the provider rotates
# refresh tokens -- and Anthropic's does -- the first trial spends the stored
# refresh token, the replacement is discarded, and EVERY later trial fails with
# "OAuth session expired and could not be refreshed". That is what happened on
# the second trial ever run here: one good result, then a dead grid.
#
# Only the credential file goes back, so the channel between trials carries an
# access token and nothing about the task, the layout or the codebase.
REFRESHABLE = %w[.credentials.json auth.json].freeze

def private_config(source, dest)
  return nil unless source && Dir.exist?(source)

  FileUtils.rm_rf(dest)
  FileUtils.mkdir_p(dest)
  SEEDED.each do |f|
    from = File.join(source, f)
    FileUtils.cp(from, File.join(dest, f)) if File.exist?(from)
  end
  dest
end

# Never write back a credential that is worse than the one already stored.
#
# A CLI that fails to authenticate does not leave the file alone: it BLANKS it,
# writing back the same JSON shape with empty strings where the tokens were.
# Copying that to the shared store turns one dead trial into a permanently
# destroyed login, and it does it silently, because the file is still valid JSON
# of the right shape and still passes `auth status`.
#
# Found the honest way, by doing it. The tokens involved were already spent, so
# nothing recoverable was lost, but the next time they would not be.
#
# The rule: a field that holds a non-empty string in the stored file may not
# become empty in the candidate.
def downgrade?(stored, candidate)
  old = JSON.parse(stored)
  new = JSON.parse(candidate)
  flatten = lambda do |value, into = {}|
    case value
    when Hash then value.each { |k, v| v.is_a?(Hash) ? flatten.call(v, into) : into[k] = v }
    end
    into
  end
  before = flatten.call(old)
  after = flatten.call(new)
  before.any? { |k, v| v.is_a?(String) && !v.empty? && after[k].is_a?(String) && after[k].empty? }
rescue JSON::ParserError
  # Unparsable is not something to reason about; refuse it.
  true
end

def persist_refreshed_credentials(source, dest)
  return [] unless source && dest && Dir.exist?(source) && Dir.exist?(dest)

  REFRESHABLE.filter_map do |name|
    from = File.join(dest, name)
    to = File.join(source, name)
    next unless File.exist?(from)

    candidate = File.read(from)
    stored = File.exist?(to) ? File.read(to) : nil
    next if stored == candidate

    if stored && downgrade?(stored, candidate)
      log "refusing to write #{name} back: the agent left it with empty credentials"
      next
    end

    begin
      FileUtils.cp(from, to)
      name
    rescue StandardError => e
      log "could not write refreshed #{name} back: #{e.class}: #{e.message}"
      nil
    end
  end
end

shared_config = agent == "claude" ? ENV["CLAUDE_CONFIG_DIR"] : ENV["CODEX_HOME"]
private_dir = private_config(shared_config,
                             agent == "claude" ? "/home/agent/.claude-trial" : "/home/agent/.codex-trial")
if private_dir
  ENV[agent == "claude" ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"] = private_dir
end
meta["config_dir"] = agent == "claude" ? ENV["CLAUDE_CONFIG_DIR"] : ENV["CODEX_HOME"]

# --- run the agent ------------------------------------------------------------
transcript = File.join(RESULTS, "transcript.jsonl")

cmd =
  case agent
  when "claude"
    base = ["claude", "-p", "--output-format", "stream-json", "--verbose",
            "--permission-mode", "bypassPermissions"]
    base += ["--model", model] if model
    base
  when "codex"
    base = ["codex", "exec", "--json",
            "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check", "--ignore-user-config", "--ephemeral",
            "-C", APP_DIR]
    base += ["--model", model] if model
    base << "-"
  else
    abort "unknown agent #{agent}"
  end

meta["agent_argv"] = cmd
log "running #{cmd.join(' ')}"

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
agent_exit = nil
timed_out = false

File.open(transcript, "w") do |sink|
  Open3.popen3({}, *cmd, chdir: APP_DIR) do |stdin, stdout, stderr, wait|
    stdin.write(prompt)
    stdin.close

    err_buf = +""
    err_thread = Thread.new { stderr.each_line { |l| err_buf << l } }
    out_thread = Thread.new { stdout.each_line { |line| sink.write(line); sink.flush } }

    unless wait.join(timeout_s)
      timed_out = true
      begin
        Process.kill("KILL", wait.pid)
      rescue StandardError
        nil
      end
    end
    out_thread.join(10)
    err_thread.join(5)
    agent_exit = begin
      wait.value.exitstatus
    rescue StandardError
      nil
    end
    File.write(File.join(RESULTS, "agent_stderr.txt"), err_buf)
  end
end

meta["agent_exit"] = agent_exit
meta["timed_out"] = timed_out
meta["wall_seconds"] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
log "agent finished in #{meta['wall_seconds']}s (exit #{agent_exit}, timeout #{timed_out})"

# Immediately, and before anything that can fail. A refreshed token stranded in
# the private copy is what kills every subsequent trial.
refreshed = persist_refreshed_credentials(shared_config, private_dir)
meta["credentials_refreshed"] = refreshed
log "wrote refreshed credentials back: #{refreshed.join(', ')}" if refreshed.any?

# --- the agent's closing words ------------------------------------------------
#
# The locate tasks are answered in prose, not in the repository, so the final
# message is the deliverable and the acceptance check needs it as a file. The
# two CLIs report it differently, so it is extracted here, once, rather than in
# every check.
def final_message(path)
  events = File.readlines(path).filter_map do |line|
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end

  claude = events.reverse.find { |e| e["type"] == "result" }
  return claude["result"].to_s if claude && claude["result"]

  codex = events.reverse.find { |e| e["type"] == "item.completed" && e.dig("item", "type") == "agent_message" }
  return codex.dig("item", "text").to_s if codex

  # Fall back to the last assistant text block, which is what a transcript
  # truncated by a timeout leaves behind.
  assistant = events.reverse.find { |e| e["type"] == "assistant" }
  Array(assistant&.dig("message", "content")).select { |c| c["type"] == "text" }
                                             .map { |c| c["text"] }.join("\n")
end

answer = begin
  final_message(transcript)
rescue StandardError => e
  log "could not extract a final message: #{e.class}"
  ""
end
File.write(File.join(RESULTS, "answer.txt"), answer)

# --- did the agent actually get a turn? ---------------------------------------
#
# A trial can die on a transient API error: the CLI exits, the transcript holds
# a result event with is_error and zero tokens everywhere, and no work was ever
# attempted. That is a broken cell to run again, NOT an agent that failed the
# task, and the two must not look the same afterwards -- scored as a failure it
# would drag down whichever condition happened to be running when the API
# hiccuped, which is a bias with no relation to layout.
#
# Observed here on the second trial ever run, back to back with the first.
def api_error(path)
  events = File.readlines(path).filter_map do |line|
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end

  result = events.reverse.find { |e| e["type"] == "result" }
  if result
    usage = result["usage"] || {}
    spent = %w[input_tokens output_tokens cache_creation_input_tokens
               cache_read_input_tokens].sum { |k| usage[k].to_i }
    return result["terminal_reason"] if result["is_error"] && spent.zero?
  end

  # Codex reports failure as an error item rather than a result envelope.
  fatal = events.reverse.find { |e| e["type"] == "item.completed" && e.dig("item", "type") == "error" }
  return "codex_error" if fatal && events.none? { |e| e["type"] == "turn.completed" }

  nil
end

if (reason = (api_error(transcript) rescue nil))
  log "FATAL: the agent never got a turn (#{reason}); not scoring this as a failed trial"
  meta["aborted"] = "api_error"
  meta["api_error_reason"] = reason
  meta["passed"] = nil
  File.write(File.join(RESULTS, "meta.json"), JSON.pretty_generate(meta))
  exit 5
end

# --- what did it change? ------------------------------------------------------
#
# Recorded BEFORE the acceptance check runs. The check writes a test file of its
# own and applies mutations, and a diff taken afterwards would attribute all of
# that to the agent.
diff = run("git diff")
File.write(File.join(RESULTS, "agent.diff"), diff["stdout"])
meta["changed_files"] = run("git diff --name-only")["stdout"].split("\n").map(&:strip).reject(&:empty?)
meta["untracked_files"] = run("git ls-files --others --exclude-standard")["stdout"]
                          .split("\n").map(&:strip).reject(&:empty?)
meta["touched_target"] = (meta["changed_files"] & targets).any?

# --- acceptance ---------------------------------------------------------------
#
# A missing check is a broken harness, not a failed trial, and the two must not
# look the same in the results: `passed` would come out false and the trial
# would be read as an agent that got the task wrong. Fail loudly instead.
check_path = check_file && !check_file.empty? ? File.join(RESULTS, "checks", "task", check_file) : nil
if check_path && !File.exist?(check_path)
  log "FATAL: #{check_path} was not copied into the container"
  meta["aborted"] = "acceptance_check_missing"
  File.write(File.join(RESULTS, "meta.json"), JSON.pretty_generate(meta))
  exit 4
end

if check_path
  log "running acceptance check #{File.basename(check_file)}"
  result = run("ruby #{check_path}", timeout: 3000,
               env: { "LLMX_TASK" => task_id, "LLMX_VARIANT" => variant,
                      "LLMX_TARGETS" => targets.join(","),
                      "LLMX_REGRESSION_SUITE" => cfg(:regression_suite, "1") })
  File.write(File.join(RESULTS, "acceptance.log"), result["stdout"] + result["stderr"])
  meta["acceptance_exit"] = result["exit"]
  meta["acceptance_seconds"] = result["seconds"]

  acceptance_path = File.join(RESULTS, "acceptance.json")
  meta["passed"] = File.exist?(acceptance_path) &&
                   JSON.parse(File.read(acceptance_path))["passed"] == true
else
  log "no acceptance check for #{task_id}"
  meta["passed"] = nil
end

meta["toolchain"] = begin
  JSON.parse(File.read("/etc/llmx-versions.json"))
rescue StandardError
  nil
end
meta["finished_at"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")

File.write(File.join(RESULTS, "meta.json"), JSON.pretty_generate(meta))
log "wrote #{File.join(RESULTS, 'meta.json')} (passed: #{meta['passed'].inspect})"
exit 0
