#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the grid.
#
#   ruby convention-navigation/scripts/run_grid.rb --dry-run
#   ruby convention-navigation/scripts/run_grid.rb
#   ruby convention-navigation/scripts/run_grid.rb --agent codex --repeats 5
#   ruby convention-navigation/scripts/run_grid.rb --conditions conventional,scrambled
#
# Phase 1 is 4 tasks x 2 conditions x 2 agents x 5 repeats = 80 trials.
#
# FIVE REPEATS, NOT THREE. This repository has already had to retract claims
# built on three runs, and agent trials vary more than the effect being chased:
# the same prompt on the same tree can take four tool calls or fourteen. Three
# points cannot tell those apart from a real difference.
#
# ORDER. The comparison is within a task, so the grid is blocked by task: all of
# one task's cells run close together, and a slow patch of machine time lands on
# every condition of that task rather than on one of them. Within a block the
# condition order rotates with the repeat index, so no condition is always first
# and no condition is always last.
#
# SEQUENTIAL ON PURPOSE. Two trials at once share the machine and contaminate
# wall_seconds. That already happened once in at-file-mentions and made a whole
# app's timings unusable.

require "fileutils"
require "json"
require_relative "../../containers/scripts/lib/kit"

DEFAULT_CONDITIONS = %w[conventional scrambled].freeze
AGENTS = %w[claude codex].freeze

dry_run = false
only_agent = nil
only_task = nil
repeats = 5
conditions = DEFAULT_CONDITIONS.dup

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--dry-run" then dry_run = true
  when "--agent" then only_agent = args.shift
  when "--task" then only_task = args.shift
  when "--repeats" then repeats = args.shift.to_i
  when "--conditions" then conditions = args.shift.to_s.split(",")
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

EXPERIMENT_DIR = File.expand_path("..", __dir__)
RAW = File.join(EXPERIMENT_DIR, "results-raw")

tasks = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "tasks.yml"))["tasks"]
tasks = tasks.select { |t| t["id"] == only_task } if only_task
abort "no tasks match" if tasks.empty?

agents = only_agent ? [only_agent] : AGENTS
bad = agents - AGENTS
abort "unknown agent(s): #{bad.inspect}" if bad.any?

# How many usable runs a cell already has. A run that aborted before the agent
# got a turn does not count: it produced no data, and counting it would quietly
# shrink the sample instead of retrying the cell.
def completed(task_id, agent, condition)
  Dir.glob(File.join(RAW, task_id, agent, condition, "*", "meta.json")).count do |path|
    JSON.parse(File.read(path))["aborted"].nil?
  rescue StandardError
    false
  end
end

plan = []
tasks.each do |task|
  (1..repeats).each do |repeat|
    ordered = conditions.rotate((repeat - 1) % conditions.size)
    agents.each do |agent|
      ordered.each do |condition|
        plan << { task: task["id"], agent: agent, condition: condition, repeat: repeat }
      end
    end
  end
end

# Counted per cell rather than per planned row: five planned repeats of a cell
# that already has two runs means three to do, whichever rows they were.
have = Hash.new { |h, k| h[k] = completed(*k) }
todo = []
plan.each do |cell|
  key = [cell[:task], cell[:agent], cell[:condition]]
  next if have[key] >= repeats

  have[key] += 1
  todo << cell
end

puts "grid: #{plan.size} planned, #{todo.size} to run, #{plan.size - todo.size} already have results"
puts "      #{tasks.size} task(s) x #{conditions.size} condition(s) x #{agents.size} agent(s) x #{repeats} repeat(s)"
puts

if dry_run
  todo.each { |c| puts format("  %-24s %-7s %-18s repeat %d", c[:task], c[:agent], c[:condition], c[:repeat]) }
  puts "\n(dry run: nothing was executed)"
  exit 0
end

failures = []
aborted = []
started = Time.now

todo.each_with_index do |cell, i|
  label = format("%s / %s / %s (repeat %d)", cell[:task], cell[:agent], cell[:condition], cell[:repeat])
  Kit.log "[#{i + 1}/#{todo.size}] #{label}"

  cmd = ["ruby", File.join(__dir__, "run_trial.rb"),
         "--task", cell[:task], "--agent", cell[:agent], "--condition", cell[:condition]]

  # One bad cell must not cost the rest of the grid. run_trial.rb exits 2 for a
  # cell that produced no data at all, which is a different thing from a trial
  # where the agent ran and did badly, and the two are reported separately.
  ok = system(*cmd)
  next if ok

  status = $?&.exitstatus
  if status == 2
    aborted << label
    Kit.log "  ABORTED (no data): #{label}"
  else
    failures << label
    Kit.log "  FAILED (exit #{status.inspect}): #{label}"
  end
end

elapsed = (Time.now - started).round
puts
puts "ran #{todo.size - failures.size - aborted.size}/#{todo.size} cell(s) in #{elapsed}s"

if aborted.any?
  puts "\n#{aborted.size} cell(s) produced no data and should be re-run:"
  aborted.each { |a| puts "  #{a}" }
  puts "\nRe-running the grid picks these up automatically; they are not counted as done."
end

if failures.any?
  puts "\n#{failures.size} cell(s) failed for another reason:"
  failures.each { |f| puts "  #{f}" }
  exit 1
end

puts "\nnext: ruby convention-navigation/scripts/parse_transcript.rb --all"
puts "      ruby convention-navigation/scripts/metrics.rb"
puts "      ruby convention-navigation/scripts/sanitize.rb"
