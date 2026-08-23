#!/usr/bin/env ruby
# frozen_string_literal: true

# The gate between results-raw/ (gitignored) and results/ (committed).
#
#   ruby convention-navigation/scripts/sanitize.rb
#   ruby convention-navigation/scripts/sanitize.rb --check   # report, copy nothing
#
# A transcript contains whatever source the agent read, so for a private app
# only the derived measurements cross. campfire is MIT, so its transcripts cross
# whole.
#
# The check is a hard failure rather than a redaction. Something unexpected in a
# transcript should stop the commit and be looked at, not be quietly rewritten
# into something that looks safe.

require "fileutils"
require "json"
require_relative "../../containers/scripts/lib/kit"

check_only = ARGV.include?("--check")

EXPERIMENT_DIR = File.expand_path("..", __dir__)
RAW = File.join(EXPERIMENT_DIR, "results-raw")
OUT = File.join(EXPERIMENT_DIR, "results")

apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
PUBLIC_APPS = apps.select { |a| a["commit_raw_transcripts"] }.map { |a| a["key"] }

# Anything matching these must never reach the committed tree, whatever the
# app's privacy setting. Host paths identify the machine; the rest are secrets.
#
# The OAuth pattern is here because this experiment writes refreshed credentials
# back to the shared store, and a transcript that captured one would otherwise
# be committed. Nothing has ever matched it, which is the point of having it.
FORBIDDEN = {
  "host home path" => %r{/Users/[a-z]},
  "AWS-style key" => /AKIA[0-9A-Z]{16}/,
  "private key block" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  "bearer token" => /\b(?:sk|pk)-[A-Za-z0-9_-]{20,}/,
  "oauth token" => /\bsk-ant-oat[A-Za-z0-9_-]{10,}/,
  "rails master key" => /\b[0-9a-f]{32}\b(?=.*master)/i,
  "generic api secret" => /(?:api[_-]?key|secret|password|token)["'\s:=]+[A-Za-z0-9_\-]{24,}/i
}.freeze

def scan(text, label)
  FORBIDDEN.filter_map do |name, pattern|
    next unless (m = text[pattern])

    { "file" => label, "kind" => name, "sample" => m[0, 40] }
  end
end

trials = Dir.glob(File.join(RAW, "**", "meta.json")).map { |p| File.dirname(p) }.sort
abort "nothing in results-raw/ yet" if trials.empty?

violations = []
copied = 0
skipped = 0

trials.each do |dir|
  meta = JSON.parse(File.read(File.join(dir, "meta.json")))

  # A trial that never got the agent a turn is not a result. Publishing it would
  # put rows in results/ that metrics.rb deliberately ignores, and anyone
  # counting directories would get a different n from anyone reading the data.
  if meta["aborted"]
    skipped += 1
    next
  end

  app = meta["app"]
  public_app = PUBLIC_APPS.include?(app)
  rel = dir.sub(RAW + "/", "")
  target = File.join(OUT, rel)

  crossing = %w[meta.json metrics.json prompt.txt answer.txt acceptance.json]
  if public_app
    crossing += %w[transcript.jsonl events.jsonl agent.diff acceptance.log db_prepare.txt]
  end

  crossing.each do |name|
    src = File.join(dir, name)
    next unless File.exist?(src)

    violations.concat(scan(File.read(src), File.join(rel, name)))
  end

  next if check_only

  FileUtils.mkdir_p(target)
  crossing.each do |name|
    src = File.join(dir, name)
    next unless File.exist?(src)

    FileUtils.cp(src, File.join(target, name))
    copied += 1
  end

  next if public_app

  File.write(File.join(target, "README.md"), <<~MD)
    Private application. Raw transcripts and diffs stay in `results-raw/`,
    which is gitignored; only the measurements derived from them are here.

    - `meta.json` what the trial did and whether it passed
    - `metrics.json` the numbers `metrics.rb` reads
    - `prompt.txt` the exact prompt, which contains no application source
    - `answer.txt` the agent's closing message
    - `acceptance.json` the scripted verdict and the facts behind it
  MD
end

if violations.any?
  warn "REFUSING to publish. #{violations.size} problem(s):\n"
  violations.first(40).each { |v| warn format("  %-56s %-18s %s", v["file"], v["kind"], v["sample"].inspect) }
  unless check_only
    warn "\nNothing was copied."
    FileUtils.rm_rf(OUT)
  end
  exit 1
end

if check_only
  puts "checked #{trials.size - skipped} trial(s): clean (#{skipped} aborted, not published)"
else
  puts "published #{copied} file(s) from #{trials.size - skipped} trial(s) to results/"
  puts "skipped #{skipped} aborted trial(s), which produced no data"
  puts "raw transcripts committed only for: #{PUBLIC_APPS.join(', ')}"
end
