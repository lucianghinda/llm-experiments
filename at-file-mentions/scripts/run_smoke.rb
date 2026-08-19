#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the smoke set: enough trials to exercise every app, both agents and all
# three conditions at least once, without running the full grid.
#
#   ruby at-file-mentions/scripts/run_smoke.rb
#   ruby at-file-mentions/scripts/run_smoke.rb --dry-run
#
# This is a harness check, not an experiment. The conditions are spread across
# apps so each rendering gets exercised; the numbers it produces are one sample
# each and mean nothing on their own.

require "json"
require_relative "../../containers/scripts/lib/kit"

dry_run = ARGV.include?("--dry-run")

EXPERIMENT_DIR = File.expand_path("..", __dir__)
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]

# One trial per app for Claude, cycling the live conditions, plus one Codex
# trial on the public app so the second agent's transcript format is exercised
# too.
#
# One bug per app, not every bug. This used to map over the whole of bugs.yml,
# which was the same thing back when there were three bugs; at five per app it
# would quietly become a 16-trial run, which is a grid, not a smoke check.
#
# The conditions here are the three the grid still runs. `bare` and `at` are
# inert - a :line suffix stops the mention resolving - so smoking them exercises
# nothing that bare_noline and at_noline do not.
CONDITIONS = %w[none bare_noline at_noline].freeze

one_per_app = bugs.group_by { |b| b["app"] }.values.map(&:first)
plan = one_per_app.each_with_index.map do |bug, i|
  { bug: bug["id"], agent: "claude", condition: CONDITIONS[i % CONDITIONS.size] }
end
public_bug = one_per_app.find { |b| b["app"] == "campfire" }
plan << { bug: public_bug["id"], agent: "codex", condition: "at_noline" } if public_bug

puts "smoke set (#{plan.size} trials):"
plan.each { |t| puts format("  %-20s %-8s %s", t[:bug], t[:agent], t[:condition]) }
puts

results = []
plan.each do |trial|
  cmd = ["ruby", File.join(__dir__, "run_trial.rb"),
         "--bug", trial[:bug], "--agent", trial[:agent], "--condition", trial[:condition]]
  cmd << "--dry-run" if dry_run

  puts "\n#{'=' * 70}\n#{trial[:bug]} / #{trial[:agent]} / #{trial[:condition]}\n#{'=' * 70}"
  ok = system(*cmd)
  results << trial.merge(ok: ok)
end

puts "\n#{'=' * 70}\nsmoke summary\n#{'=' * 70}"
results.each { |r| puts format("  %-20s %-8s %-6s %s", r[:bug], r[:agent], r[:condition], r[:ok] ? "ran" : "FAILED") }

failed = results.reject { |r| r[:ok] }
if failed.any?
  warn "\n#{failed.size} trial(s) failed. Look in results-raw/, or open a shell with"
  warn "  ruby containers/scripts/trial_shell.rb --app <key>"
  exit 1
end

puts "\nNow: ruby at-file-mentions/scripts/parse_transcript.rb --all"
