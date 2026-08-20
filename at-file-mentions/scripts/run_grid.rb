#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the full grid: every bug, both agents, the three conditions that are
# still live.
#
#   ruby at-file-mentions/scripts/run_grid.rb --dry-run
#   ruby at-file-mentions/scripts/run_grid.rb
#   ruby at-file-mentions/scripts/run_grid.rb --app campfire --agent claude
#
# Three conditions, not five. `bare` (path:line) and `at` (@path:line) are both
# inert: a line suffix stops the mention resolving, so the two forms differ by
# exactly one token and nothing is attached. That was measured three times and
# came out +2 tokens every time. render_prompts.rb still renders all five,
# because its cross-family identity checks are what guarantee a difference is
# attributable to the line number alone - but there is no reason to spend
# container time re-running a settled answer.
#
#   15 bugs x 3 conditions x 2 agents = 90 trials
#
# Order matters. The comparison is within a bug, so the grid is blocked by bug:
# all of one bug's cells run close together, and a slow patch of machine time
# lands on every condition of that bug rather than on one of them. Within a
# block the condition order rotates with the bug index, so no condition always
# runs first or always runs last.
#
# Sequential on purpose. Two trials at once share the machine and contaminate
# wall_seconds - that already happened once, to the postcraftstudio _noline
# cells, and made their timings unusable.

require "fileutils"
require "json"
require_relative "../../containers/scripts/lib/kit"

CONDITIONS = %w[none bare_noline at_noline].freeze
AGENTS = %w[claude codex].freeze

dry_run = false
only_app = nil
only_agent = nil
only_bug = nil
redo_done = false

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--dry-run" then dry_run = true
  when "--app" then only_app = args.shift
  when "--agent" then only_agent = args.shift
  when "--bug" then only_bug = args.shift
  when "--redo" then redo_done = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

EXPERIMENT_DIR = File.expand_path("..", __dir__)
RAW = File.join(EXPERIMENT_DIR, "results-raw")

bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]
bugs = bugs.select { |b| b["app"] == only_app } if only_app
bugs = bugs.select { |b| b["id"] == only_bug } if only_bug
abort "no bugs match" if bugs.empty?

agents = only_agent ? [only_agent] : AGENTS
bad = agents - AGENTS
abort "unknown agent(s): #{bad.inspect}" if bad.any?

# A cell is done when it has at least one run that got as far as writing meta.
def done?(bug_id, agent, condition)
  Dir.glob(File.join(RAW, bug_id, agent, condition, "*", "meta.json")).any?
end

plan = []
bugs.each_with_index do |bug, i|
  # Rotate so condition position within a block varies across bugs.
  ordered = CONDITIONS.rotate(i % CONDITIONS.size)
  agents.each do |agent|
    ordered.each do |condition|
      plan << { bug: bug["id"], agent: agent, condition: condition }
    end
  end
end

skipped = plan.select { |c| !redo_done && done?(c[:bug], c[:agent], c[:condition]) }
todo = plan - skipped

puts "grid: #{plan.size} cell(s) - #{todo.size} to run, #{skipped.size} already have results"
puts "      #{bugs.size} bug(s) x #{CONDITIONS.size} condition(s) x #{agents.size} agent(s)"
puts

if dry_run
  todo.each { |c| puts format("  %-22s %-7s %s", c[:bug], c[:agent], c[:condition]) }
  puts "\n(dry run: nothing was executed)"
  exit 0
end

failures = []
started = Time.now

todo.each_with_index do |cell, i|
  label = format("%s / %s / %s", cell[:bug], cell[:agent], cell[:condition])
  Kit.log "[#{i + 1}/#{todo.size}] #{label}"

  cmd = ["ruby", File.join(__dir__, "run_trial.rb"),
         "--bug", cell[:bug], "--agent", cell[:agent], "--condition", cell[:condition]]

  # One bad cell must not cost the other 89. Record it and carry on; the grid
  # is resumable, so a failed cell is simply re-run later.
  ok = Kit.sh(*cmd, allow_failure: true)
  next if ok

  failures << label
  Kit.log "  FAILED: #{label}"
end

elapsed = (Time.now - started).round
puts
puts "ran #{todo.size - failures.size}/#{todo.size} cell(s) in #{elapsed}s"

if failures.any?
  puts "\n#{failures.size} failed:"
  failures.each { |f| puts "  #{f}" }
  puts "\nre-run just those, then: ruby at-file-mentions/scripts/sanitize.rb"
  exit 1
end

puts "\nnext: ruby at-file-mentions/scripts/parse_transcript.rb --all"
puts "      ruby at-file-mentions/scripts/sanitize.rb"
puts "      ruby at-file-mentions/scripts/metrics.rb"
