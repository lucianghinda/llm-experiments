#!/usr/bin/env ruby
# frozen_string_literal: true

# The gate between results-raw/ (gitignored) and results/ (committed).
#
# Two of the three apps are private, so their raw transcripts cannot be
# published: a transcript contains whatever source the agent read. For those
# apps only derived measurements cross. campfire is MIT, so its transcripts
# cross whole.
#
# The check is deliberately a hard failure rather than a redaction. Something
# unexpected in a transcript should stop the commit and be looked at, not be
# quietly rewritten into something that looks safe.
#
#   ruby at-file-mentions/scripts/sanitize.rb
#   ruby at-file-mentions/scripts/sanitize.rb --check   # report, copy nothing

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
FORBIDDEN = {
  "host home path" => %r{/Users/[a-z]},
  "AWS-style key" => /AKIA[0-9A-Z]{16}/,
  "private key block" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  "bearer token" => /\b(?:sk|pk)-[A-Za-z0-9_-]{20,}/,
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

trials.each do |dir|
  meta = JSON.parse(File.read(File.join(dir, "meta.json")))
  app = meta["app"]
  public_app = PUBLIC_APPS.include?(app)
  rel = dir.sub(RAW + "/", "")
  target = File.join(OUT, rel)

  # Derived measurements always cross. Raw transcripts only for public apps.
  crossing = ["meta.json", "metrics.json", "prompt.txt"]
  crossing += ["transcript.jsonl", "events.jsonl", "agent.diff",
               "test_before.txt", "test_after.txt"] if public_app

  crossing.each do |name|
    src = File.join(dir, name)
    next unless File.exist?(src)

    text = File.read(src)
    violations.concat(scan(text, File.join(rel, name)))
  end

  next if check_only

  FileUtils.mkdir_p(target)
  crossing.each do |name|
    src = File.join(dir, name)
    next unless File.exist?(src)

    FileUtils.cp(src, File.join(target, name))
    copied += 1
  end

  unless public_app
    File.write(File.join(target, "README.md"), <<~MD)
      Private application. Raw transcripts and diffs stay in `results-raw/`,
      which is gitignored; only the measurements derived from them are here.

      - `meta.json` what the trial did and whether the fix held
      - `metrics.json` the numbers `metrics.rb` reads
      - `prompt.txt` the exact prompt, which contains no application source
    MD
  end
end

if violations.any?
  warn "REFUSING to publish. #{violations.size} problem(s):\n"
  violations.first(40).each { |v| warn format("  %-56s %-18s %s", v["file"], v["kind"], v["sample"].inspect) }
  warn "\nNothing was copied." unless check_only
  FileUtils.rm_rf(OUT) unless check_only
  exit 1
end

if check_only
  puts "checked #{trials.size} trial(s): clean"
else
  puts "published #{copied} file(s) from #{trials.size} trial(s) to results/"
  puts "raw transcripts committed only for: #{PUBLIC_APPS.join(', ')}"
end
