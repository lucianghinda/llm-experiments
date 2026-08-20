#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs inside the trial container. run_trial.rb copies this in and starts it;
# it is never executed on the host.
#
# Order matters here. Everything that could tell the agent where the defect is
# has to be gone before the agent starts, and the test has to be observed
# failing before the agent starts, so a mis-planted bug is caught as a bad trial
# instead of being scored as an instant fix.

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
  {
    "cmd" => cmd,
    "exit" => status.exitstatus,
    "stdout" => out,
    "stderr" => err,
    "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
  }
end

def log(msg)
  warn "[runner] #{msg}"
end

branch      = cfg(:branch)      or abort "LLMX_BRANCH required"
agent       = cfg(:agent)       or abort "LLMX_AGENT required"
condition   = cfg(:condition)   or abort "LLMX_CONDITION required"
test_file   = cfg(:test_file)   or abort "LLMX_TEST_FILE required"
prompt_b64  = cfg(:prompt_b64)  or abort "LLMX_PROMPT_B64 required"
impl_files  = (cfg(:impl_files) || "").split(",")
model       = cfg(:model)
db_prepare  = cfg(:db_prepare, "bin/rails db:test:prepare")
timeout_s   = cfg(:timeout_seconds, "900").to_i
database    = cfg(:database, "sqlite3")

prompt = Base64.strict_decode64(prompt_b64)

meta = {
  "bug_id" => cfg(:bug_id),
  "app" => cfg(:app),
  "agent" => agent,
  "condition" => condition,
  "branch" => branch,
  "model_requested" => model,
  # Persisted because parse_transcript.rb needs them to compute
  # tool_calls_to_first_defect_read. Without them it matches against an empty
  # list, and the metric comes out nil on every trial while looking like a
  # null observation rather than a broken one.
  "impl_files" => impl_files,
  "test_file" => test_file,
  "started_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
}

# --- Postgres, if this app needs it -----------------------------------------
#
# The cluster is the agent user's own, created at image build, so starting it
# needs no privileges. The packaged system cluster would need root, and root is
# not something to hand a container that runs model-authored shell commands.
if database == "postgresql"
  log "starting postgres"
  pgbin = File.dirname(Dir.glob("/usr/lib/postgresql/*/bin/pg_ctl").first)
  pgdata = ENV.fetch("PGDATA", "/home/agent/pgdata")
  system("#{pgbin}/pg_ctl -D #{pgdata} -l /tmp/postgres.log -o '-p 5432' -w start > /dev/null 2>&1")
  ready = false
  30.times do
    ready = system("#{pgbin}/pg_isready -q -h 127.0.0.1 -p 5432")
    break if ready

    sleep 0.5
  end
  meta["postgres_ready"] = ready
  log "postgres ready: #{ready}"
end

# --- Isolate the branch under test ------------------------------------------
#
# The image ships every trial branch. Leaving them in place would let one
# `git diff trial/base` show the planted change, which is the answer. Delete
# everything except the branch being tested, then drop the objects so the trees
# are not merely unreferenced but gone.
log "isolating #{branch}"
run("git checkout -q #{branch}")
others = run("git branch --format=%(refname:short)")["stdout"].split("\n").map(&:strip)
              .reject { |b| b.empty? || b == branch }
others.each { |b| run("git branch -q -D #{b}") }
run("git reflog expire --expire=now --all")
run("git gc --prune=now --quiet")

visible = run("git log --all --oneline")["stdout"].strip
meta["history_visible_to_agent"] = visible
meta["branches_visible_to_agent"] = run("git branch --format=%(refname:short)")["stdout"].split("\n").map(&:strip)

dirty = run("git status --porcelain")["stdout"].strip
meta["clean_tree_before"] = dirty.empty?
log "tree clean before agent: #{dirty.empty?}"

# --- Database ----------------------------------------------------------------
prep = run(db_prepare, timeout: 300)
meta["db_prepare_exit"] = prep["exit"]
File.write(File.join(RESULTS, "db_prepare.txt"), prep["stdout"] + prep["stderr"])

# --- Confirm the bug is real before spending a trial on it -------------------
#
# A non-zero exit is not enough. An app that cannot boot also exits non-zero,
# and scoring that as "the planted bug reproduces" would spend a trial on a
# broken container and then read the agent's confusion as data. Require a
# Minitest summary line, which only appears if the suite actually ran.
before = run("bin/rails test #{test_file}", timeout: 600)
output = before["stdout"] + before["stderr"]
meta["test_before"] = { "exit" => before["exit"], "seconds" => before["seconds"] }
File.write(File.join(RESULTS, "test_before.txt"), output)

suite_ran = output.match?(/\d+ runs?, \d+ assertions?/)
meta["suite_ran_before"] = suite_ran
meta["bug_reproduces"] = suite_ran && before["exit"] != 0

unless meta["bug_reproduces"]
  reason = suite_ran ? "bug_did_not_reproduce" : "suite_did_not_run"
  log "aborting: #{reason} (see test_before.txt)"
  meta["aborted"] = reason
  File.write(File.join(RESULTS, "meta.json"), JSON.pretty_generate(meta))
  exit 3
end

# --- Give the agent a private config directory -------------------------------
#
# CLAUDE_CONFIG_DIR points at the mounted credential store, and Claude Code
# derives its project state and auto-memory directory from it: the init event
# reports memory at <config>/projects/-workspace-app/memory/. That directory is
# writable, shared by every trial and persisted on the host, which opens three
# channels between trials that are supposed to be independent:
#
#   - session transcripts accumulate under projects/
#   - .claude.json records per-project onboarding and startup state, so the
#     first trial of a grid does not start from the same place as the rest
#   - anything written to the memory directory in one trial is read by the
#     next, and in this experiment that could be the location of the defect
#
# So each trial copies the credentials into its own directory and points the
# CLI at the copy. The copy lives in the container and dies with it; the
# mounted store is only ever read, which keeps every trial starting from
# byte-identical state. Codex already has this guarantee from
# --ignore-user-config --ephemeral.
SEEDED = %w[.credentials.json .claude.json settings.json auth.json config.toml].freeze

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

if agent == "claude" && (dir = private_config(ENV["CLAUDE_CONFIG_DIR"], "/home/agent/.claude-trial"))
  ENV["CLAUDE_CONFIG_DIR"] = dir
end
if agent == "codex" && (dir = private_config(ENV["CODEX_HOME"], "/home/agent/.codex-trial"))
  ENV["CODEX_HOME"] = dir
end
meta["config_dir"] = agent == "claude" ? ENV["CLAUDE_CONFIG_DIR"] : ENV["CODEX_HOME"]

# --- Run the agent -----------------------------------------------------------
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
    out_thread = Thread.new do
      stdout.each_line do |line|
        sink.write(line)
        sink.flush
      end
    end

    unless wait.join(timeout_s)
      timed_out = true
      Process.kill("KILL", wait.pid) rescue nil
    end
    out_thread.join(10)
    err_thread.join(5)
    agent_exit = wait.value.exitstatus rescue nil
    File.write(File.join(RESULTS, "agent_stderr.txt"), err_buf)
  end
end

meta["agent_exit"] = agent_exit
meta["timed_out"] = timed_out
meta["wall_seconds"] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
log "agent finished in #{meta['wall_seconds']}s (exit #{agent_exit}, timeout #{timed_out})"

# --- What did it change? -----------------------------------------------------
diff = run("git diff")
File.write(File.join(RESULTS, "agent.diff"), diff["stdout"])
meta["changed_files"] = run("git diff --name-only")["stdout"].split("\n").map(&:strip).reject(&:empty?)
meta["untracked_files"] = run("git ls-files --others --exclude-standard")["stdout"]
                          .split("\n").map(&:strip).reject(&:empty?)
meta["touched_impl_file"] = (meta["changed_files"] & impl_files).any?
meta["edited_test_dir"] = meta["changed_files"].any? { |f| f.start_with?("test/") }

# --- Did the fix hold? -------------------------------------------------------
after = run("bin/rails test #{test_file}", timeout: 600)
after_output = after["stdout"] + after["stderr"]
meta["test_after"] = { "exit" => after["exit"], "seconds" => after["seconds"] }
File.write(File.join(RESULTS, "test_after.txt"), after_output)

# A green run only counts if the suite ran and the agent did not simply edit the
# test until it agreed with the bug.
meta["fix_verified"] = after["exit"].zero? &&
                       after_output.match?(/\d+ runs?, \d+ assertions?/) &&
                       !meta["edited_test_dir"]

meta["toolchain"] = JSON.parse(File.read("/etc/llmx-versions.json")) rescue nil
meta["finished_at"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")

File.write(File.join(RESULTS, "meta.json"), JSON.pretty_generate(meta))
log "wrote #{File.join(RESULTS, 'meta.json')}"
exit 0
