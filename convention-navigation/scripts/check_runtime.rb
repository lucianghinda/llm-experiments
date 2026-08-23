#!/usr/bin/env ruby
# frozen_string_literal: true

# The in-container half of scramble_check.rb. Never run on the host: it needs
# the app's gems and its database.
#
# Boots each variant in turn and asks three questions that the static checks
# cannot answer, because they are about what Rails does with the layout rather
# than about what is in the files.

require "json"
require "open3"

APP_DIR = "/workspace/app"
RESULTS = "/results"
VARIANTS = { "conventional" => "trial/v1", "scrambled" => "trial/v2" }.freeze

def run(cmd, timeout: nil)
  cmd = "timeout #{timeout} #{cmd}" if timeout
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  out, err, status = Open3.capture3(cmd, chdir: APP_DIR)
  { "cmd" => cmd, "exit" => status.exitstatus, "out" => out + err,
    "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1) }
end

def log(message)
  warn "[check] #{message}"
end

# Head and tail, never the tail alone. A Ruby failure puts its message at the
# top and its backtrace underneath, so keeping the last 60 lines of a broken
# suite keeps 60 lines of stack frames and throws away the one line that says
# what went wrong. That cost a container round trip to find out.
def excerpt(text, head: 40, tail: 40)
  lines = text.lines
  return text if lines.size <= head + tail

  (lines.first(head) + ["... #{lines.size - head - tail} line(s) omitted ...\n"] + lines.last(tail)).join
end

db_prepare = ENV.fetch("LLMX_DB_PREPARE", "bin/rails db:test:prepare")

if ENV.fetch("LLMX_DATABASE", "sqlite3") == "postgresql"
  pgbin = File.dirname(Dir.glob("/usr/lib/postgresql/*/bin/pg_ctl").first)
  pgdata = ENV.fetch("PGDATA", "/home/agent/pgdata")
  system("#{pgbin}/pg_ctl -D #{pgdata} -l /tmp/postgres.log -o '-p 5432' -w start > /dev/null 2>&1")
  30.times { break if system("#{pgbin}/pg_isready -q -h 127.0.0.1 -p 5432"); sleep 0.5 }
end

checks = []
routes = {}

VARIANTS.each do |variant, branch|
  log "=== #{variant} (#{branch}) ==="
  co = run("git checkout -q #{branch}")
  if co["exit"] != 0
    checks << { "label" => "#{variant}: checkout #{branch}", "ok" => false, "detail" => co["out"] }
    next
  end

  prep = run(db_prepare, timeout: 600)
  checks << { "label" => "#{variant}: #{db_prepare}", "ok" => prep["exit"].zero?, "detail" => prep["out"] }

  # zeitwerk:check eager loads every autoload path and reports what it could not
  # resolve. It is the check that catches a concerns/ directory left
  # unregistered: nothing else fails until some unrelated request touches the
  # constant that quietly moved under Concerns::.
  zeitwerk = run("bin/rails zeitwerk:check", timeout: 300)
  checks << { "label" => "#{variant}: bin/rails zeitwerk:check", "ok" => zeitwerk["exit"].zero?,
              "detail" => zeitwerk["out"] }

  listing = run("bin/rails routes", timeout: 300)
  # Prefix and Verb columns are padded to the widest entry, so two identical
  # route tables can differ in whitespace alone. Compare the fields, not the
  # rendering.
  routes[variant] = listing["out"].lines.map { |l| l.split.join(" ") }.reject(&:empty?)
  checks << { "label" => "#{variant}: bin/rails routes", "ok" => listing["exit"].zero?,
              "detail" => listing["out"] }

  suite = run("bin/rails test", timeout: 2400)
  summary = suite["out"][/\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?/]
  # A non-zero exit is not enough to fail on, and a zero exit is not enough to
  # pass on: an app that cannot boot exits non-zero without running anything,
  # and a runner that found no tests exits zero. Require the summary line.
  checks << { "label" => "#{variant}: bin/rails test (#{summary || 'no summary line'})",
              "ok" => suite["exit"].zero? && !summary.nil?,
              "detail" => excerpt(suite["out"]) }
  log "#{variant}: #{summary || 'suite produced no summary'}"
end

if routes.size == 2
  same = routes["conventional"] == routes["scrambled"]
  detail =
    if same
      ""
    else
      only_conventional = routes["conventional"] - routes["scrambled"]
      only_scrambled = routes["scrambled"] - routes["conventional"]
      (["  only on conventional:"] + only_conventional.first(15).map { |r| "    #{r}" } +
       ["  only on scrambled:"] + only_scrambled.first(15).map { |r| "    #{r}" }).join("\n")
    end
  checks << { "label" => "routes: identical on both variants " \
                         "(#{routes['conventional'].size} vs #{routes['scrambled'].size} line(s))",
              "ok" => same, "detail" => detail }
end

File.write(File.join(RESULTS, "runtime.json"),
           JSON.pretty_generate("checks" => checks,
                                "finished_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")))
exit(checks.all? { |c| c["ok"] } ? 0 : 1)
