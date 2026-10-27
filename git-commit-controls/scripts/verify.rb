#!/usr/bin/env ruby
# frozen_string_literal: true

# Re-checks every captured trial for the things that would quietly invalidate it:
# a trial that never committed, an arm whose recorded settings drifted from the
# arm table, a fixture that is not reproducible, and CLI version drift.
#
#   ruby verify.rb

require "json"
require "digest"
require "fileutils"
require "tmpdir"
require_relative "arms"

EXP = File.expand_path("..", __dir__)
RUNS = ENV.fetch("GCC_RUNS", "runs")
fails = []
notes = []

# 1. The fixture must be byte-reproducible, or arms are not comparable.
tmp = File.join(Dir.tmpdir, "gcc-verify-#{Process.pid}")
digests = 2.times.map do
  system("ruby", File.join(EXP, "scripts", "fixture.rb"), tmp, out: File::NULL)
  d = Digest::SHA256.hexdigest(`git -C #{tmp} diff --cached`)
  d
end
FileUtils.rm_rf(tmp)
if digests.uniq.size == 1
  notes << "fixture staged diff is reproducible: #{digests.first[0, 12]}"
else
  fails << "fixture is not reproducible across builds: #{digests.inspect}"
end

# 2. Every trial must have produced a commit, and its settings must match the table.
tables = { "claude" => CLAUDE_ARMS, "codex" => CODEX_ARMS, "opencode" => OPENCODE_ARMS }
counts = Hash.new(0)
Dir.glob(File.join(EXP, RUNS, "*", "*.json")).sort.each do |path|
  meta = JSON.parse(File.read(path))
  id = "#{meta['agent']}/#{meta['arm']}.#{format('%02d', meta['rep'])}"
  counts[[meta["agent"], meta["arm"]]] += 1
  fails << "#{id}: no commit was created (exit #{meta['exit']})" unless meta["committed"]

  arm = tables.fetch(meta["agent"], {})[meta["arm"]]
  next unless arm && arm[:settings].is_a?(Hash)
  expected = arm[:settings].dup
    expected = expected.merge("disableAllHooks" => true) if RUNS == "runs"
  actual = meta["settings"]
  fails << "#{id}: settings drift\n  want #{expected.to_json}\n  got  #{actual.to_json}" if expected != actual
end

# 3. Report replicate counts so a thin cell cannot be read as a strong result.
notes << "replicates per cell:"
counts.sort.each { |(agent, arm), n| notes << format("  %-9s %-30s n=%d", agent, arm, n) }

# 4. Record the toolchain the numbers belong to. For a container run that is
# what ran INSIDE the container, which is not what the host has installed.
if RUNS == "runs"
  { "claude" => "claude", "codex" => "codex", "opencode" => "opencode", "git" => "git" }.each do |name, cmd|
    v = `#{cmd} --version 2>/dev/null`.strip.split("\n").first
    notes << "#{name}: #{v} (host)"
  end
else
  # One arm deliberately varies the CLI build, so a single toolchain across the
  # whole run is NOT expected. What must hold is that each arm is internally
  # consistent, or its own replicates are not comparable with each other.
  by_arm = Hash.new { |h, k| h[k] = [] }
  Dir.glob(File.join(EXP, RUNS, "*", "*.json")).each do |f|
    j = JSON.parse(File.read(f))
    by_arm["#{j['agent']}/#{j['arm']}"] << j["versions"]
  end
  by_arm.each do |arm, sets|
    fails << "#{arm}: toolchain varies within the arm (#{sets.uniq.length} sets)" if sets.uniq.length > 1
  end
  notes << "toolchains in use (in container):"
  by_arm.values.flatten.compact.uniq.each { |v| notes << "  #{v.values.join(' | ')}" }
end

puts notes
puts
if fails.empty?
  puts "VERIFY: PASS (#{counts.values.sum} trials)"
else
  puts "VERIFY: #{fails.size} PROBLEM(S)"
  puts fails.map { |f| "  - #{f}" }
  exit 1
end
