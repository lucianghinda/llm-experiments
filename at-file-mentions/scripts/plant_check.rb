#!/usr/bin/env ruby
# frozen_string_literal: true

# Confirms each planted bug actually fails, and records how.
#
# A patch that applies backwards is not yet a bug. Later code can cover the same
# case independently, leaving the test green and the "bug" imaginary. The only
# way to know is to run the test, which is what this does, in the same image the
# trials use.
#
# Writes planted.yml: the failing test's name, its line, and a regex that
# matches its failure message. render_prompts.rb uses the line so cond-bare and
# cond-at point at the test that actually fails rather than at whichever test
# the fix commit happened to add first.
#
#   ruby at-file-mentions/scripts/plant_check.rb
#   ruby at-file-mentions/scripts/plant_check.rb --bug campfire-01

require "json"
require_relative "../../containers/scripts/lib/kit"

only_bug = nil
args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--bug" then only_bug = args.shift
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

EXPERIMENT_DIR = File.expand_path("..", __dir__)
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]

# planted.yml is committed, and for a private app a test name and a failure
# message are that app's own words. They gave away more than the prompts did:
# a test called "http basic auth is disabled" states a live configuration, and
# an assertion diff can print a real response schema or a record's attributes.
#
# sanitize.rb guards results/ and never saw this file, because planted.yml sits
# outside it. Only test_line is read by anything (render_prompts.rb); the other
# two fields are diagnostics. So they are kept for apps that already publish
# raw transcripts, and dropped for the rest.
PUBLIC_APPS = apps.select { |a| a["commit_raw_transcripts"] }.map { |a| a["key"] }

def app_of(bugs, id)
  bugs.find { |b| b["id"] == id }&.fetch("app", nil)
end

Kit.ensure_system_started!

# Minitest prints failures and errors in two different shapes, and only one of
# them carries the test's own location.
#
#   Failure:
#   ClassTest#test_name [test/foo_test.rb:42]:
#   Expected false to be truthy.
#
#   Error:
#   ClassTest#test_name:
#   NoMethodError: undefined method 'x' for an instance of Account
#       app/controllers/foo_controller.rb:41:in 'bar'
#       test/foo_test.rb:37:in 'block in <class:FooTest>'
#
# An exception has no bracketed location, because it is raised wherever it is
# raised; the test file appears only in the backtrace. Matching the bracketed
# shape alone therefore scored every raising bug as "NOT A BUG", which is wrong:
# a planted defect that raises is still a planted defect. It cost campfire-03 a
# rejection - reverting that fix makes the controller call a method the account
# does not have, so the suite reports 0 failures and 3 errors, and the old regex
# saw neither.
#
# runner.rb never had this problem: it asks whether the suite ran and whether
# the exit was non-zero. Only this pre-flight gate was affected.
def problems(body, test_file)
  found = []

  body.scan(
    /^[ \t]*(Failure|Error):[ \t]*\r?\n(.*?)(?=^[ \t]*(?:Failure|Error):[ \t]*\r?\n|^bin\/rails test |\z)/m
  ) do |kind, block|
    lines = block.lines.map(&:chomp)
    header = lines.shift.to_s.strip
    next if header.empty?

    message = lines.find { |l| !l.strip.empty? }.to_s.strip

    if (m = header.match(/\A(\S+?)\s*\[([^\]:]+):(\d+)\]:\z/))
      name = m[1]
      file = m[2]
      line = m[3].to_i
      next unless file.end_with?(test_file)
    else
      name = header.sub(/:\z/, "")
      # First backtrace frame inside the test file. `bin/rails test <file>` runs
      # only that file, so an error with no such frame still belongs to it; keep
      # it, with no line rather than a wrong one.
      frame = lines.find { |l| l.include?("#{test_file}:") }
      file = test_file
      line = frame ? frame[/#{Regexp.escape(test_file)}:(\d+)/, 1].to_i : nil
    end

    found << [name, file, line, message]
  end

  found
end

def check(app, bug)
  image = "llmx-app-#{app['key']}:latest"
  return { ok: false, error: "image #{image} not found" } unless Kit.image_exists?(image)

  # The agent-owned cluster at $PGDATA, exactly as runner.rb starts it. The
  # earlier `pg_ctlcluster ... main start` reached for the packaged system
  # cluster, which is the one the image deliberately does not use because
  # starting it needs root. It always failed, `|| true` swallowed it, db_prepare
  # then failed silently too, and Rails could not connect - so no Minitest
  # failure ever matched and every Postgres bug was reported as "NOT A BUG".
  start_pg =
    if app["database"] == "postgresql"
      'PGBIN=$(dirname $(ls /usr/lib/postgresql/*/bin/pg_ctl | head -1)); ' \
        '$PGBIN/pg_ctl -D "${PGDATA:-/home/agent/pgdata}" -l /tmp/postgres.log ' \
        '-o "-p 5432" -w start >/dev/null 2>&1 || true'
    else
      "true"
    end

  script = <<~SH
    set -e
    #{start_pg}
    cd /workspace/app
    git checkout -q trial/#{bug['id']}
    #{app['db_prepare']} >/dev/null 2>&1 || true
    echo "===BEGIN==="
    bin/rails test #{bug['test_file']} 2>&1 || true
    echo "===END==="
  SH

  # Retry once: a container started against a freshly built image can come back
  # with nothing at all, and reporting that as "the bug does not reproduce" would
  # send someone off to re-pick a bug that was fine.
  body = nil
  out = nil
  2.times do
    out, = Kit.try("container", "run", "--rm", *Kit.run_args(mount_auth: false),
                   image, "bash", "-lc", script)
    body = out[/===BEGIN===\n(.*?)===END===/m, 1].to_s
    break unless body.strip.empty?

    Kit.log "no output from #{image}; retrying once"
  end
  return { ok: false, error: "no test output\n#{out.to_s[-800..] || out}" } if body.strip.empty?

  in_test_file = problems(body, bug["test_file"])

  counts = body[/^(\d+) runs?, .*?(\d+) failures?, (\d+) errors?/]

  # A missing Minitest summary means the suite never ran - the app failed to
  # boot, or the database was unreachable. That is not the same as "the test
  # passes", and reporting it as such sends someone off to re-pick a bug that
  # was fine. runner.rb makes the same distinction before spending a trial.
  return { ok: false, error: "suite did not run (no Minitest summary)\n#{body.strip.lines.last(12).join}" } if counts.nil?

  {
    ok: !in_test_file.empty?,
    summary: counts,
    failures: in_test_file.map do |(name, file, line, message)|
      { "test" => name, "file" => file, "line" => line, "message" => message.strip.lines.first.to_s.strip }
    end,
    raw: body
  }
end

results = []
bugs.each do |bug|
  next if only_bug && bug["id"] != only_bug

  app = apps.find { |a| a["key"] == bug["app"] } or abort "unknown app for #{bug['id']}"
  Kit.log "checking #{bug['id']}"
  r = check(app, bug)
  results << [bug, r]

  if r[:ok]
    f = r[:failures].first
    puts format("  %-22s FAILS as planted -> %s:%d", bug["id"], File.basename(f["file"]), f["line"])
    puts format("  %-22s   %s", "", f["message"][0, 100])
  else
    puts format("  %-22s NOT A BUG: %s", bug["id"], r[:error] || "test passes; #{r[:summary]}")
  end
end

good = results.select { |(_, r)| r[:ok] }

# Merge rather than replace. Running with --bug checks one bug, and rewriting
# the file from that one result would silently drop every other bug's proof,
# sending render_prompts.rb back to guessing their line numbers.
planted_path = File.join(EXPERIMENT_DIR, "planted.yml")
existing = File.exist?(planted_path) ? (Kit::TinyYAML.load_file(planted_path)["planted"] || []) : []
entries = existing.to_h { |e| [e["id"], e] }

good.each do |(bug, r)|
  f = r[:failures].first
  entries[bug["id"]] = {
    "id" => bug["id"],
    "failing_test" => f["test"],
    "test_line" => f["line"],
    "failure_message" => f["message"].gsub('"', "'"),
    "failures_in_test_file" => r[:failures].size
  }
end

# A bug that was checked and did not reproduce loses its entry: a stale proof is
# worse than none, because the prompts would keep pointing at it.
results.reject { |(_, r)| r[:ok] }.each { |(bug, _)| entries.delete(bug["id"]) }

lines = []
lines << "# Generated by scripts/plant_check.rb. Do not edit."
lines << "#"
lines << "# Proof that each planted bug really fails, and where. The line here is the"
lines << "# failing test's line, which is what the bare and at prompts point at."
lines << ""
lines << "planted:"
entries.values.sort_by { |e| e["id"] }.each do |e|
  public_app = PUBLIC_APPS.include?(app_of(bugs, e["id"]))
  lines << "  - id: #{e['id']}"
  if public_app
    lines << "    failing_test: \"#{e['failing_test']}\""
  else
    lines << "    failing_test: withheld  # private app; see Layout in README"
  end
  lines << "    test_line: #{e['test_line']}"
  if public_app
    lines << "    failure_message: \"#{e['failure_message']}\""
  else
    lines << "    failure_message: withheld"
  end
  lines << "    failures_in_test_file: #{e['failures_in_test_file']}"
end
lines << ""

File.write(planted_path, lines.join("\n"))
puts "\nplanted.yml holds #{entries.size} verified bug(s); this run checked #{results.size}, #{good.size} reproduced"

bad = results.reject { |(_, r)| r[:ok] }
unless bad.empty?
  warn "\n#{bad.size} bug(s) did not reproduce. Re-pick them with probe_candidates.rb:"
  bad.each { |(bug, _)| warn "  #{bug['id']}" }
  exit 1
end
