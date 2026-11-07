#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

REPORT_DIR = ARGV.fetch(0, "/Users/luciang/Dropbox/workprojects/explorations/llm-experiments/plugin-simplicity/reports/pilot-20261102")
SUMMARY_PATH = File.join(REPORT_DIR, "summary.json")
REVIEWS_PATH = File.join(REPORT_DIR, "review-findings-final", "review-findings.json")
OUTPUT_PATH = File.join(REPORT_DIR, "FINDINGS.md")
MODEL_LABELS = {"claude" => "claude-opus-5", "codex" => "gpt-5.6-terra"}.freeze
CONDITION_LABELS = {"baseline" => "baseline", "ruby-plainspoken" => "ruby-plainspoken", "rubypowers" => "rubypowers"}.freeze

def require_condition(condition, message)
  raise message unless condition
end

def review_complete?(reviews, tasks, correct_by_task)
  batches = reviews["batches"]
  return false unless batches.is_a?(Array) && batches.map { |batch| batch["batch"] }.sort == tasks.sort

  batches.all? do |batch|
    expected = batch["expected_reviewers"]
    received = batch["reviewers"]
    count = batch["expected_packet_count"]
    expected_correct = correct_by_task.fetch(batch["batch"], 0)
    batch["status"] == "complete" &&
      batch["missing_reviewers"] == [] &&
      expected.is_a?(Array) && expected.sort == %w[luna terra] &&
      received.is_a?(Hash) && count == expected_correct &&
      expected.all? { |name| received[name].is_a?(Hash) && received[name].length == count }
  end
end

def median(values)
  sorted = values.grep(Numeric).sort
  return "unknown" if sorted.empty?

  middle = sorted.length / 2
  sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
end

def format_seconds(value)
  value.is_a?(Numeric) ? format("%.1f", value) : value.to_s
end

def format_number(value)
  value.is_a?(Numeric) ? format("%.1f", value) : value.to_s
end

summary = JSON.parse(File.read(SUMMARY_PATH))
reviews = JSON.parse(File.read(REVIEWS_PATH))
cells = summary.fetch("cells")
tasks = cells.map { |cell| cell.dig("cell", "task") }.uniq.sort
terminal_dispositions = %w[complete task_failure agent_failure infrastructure_failure timeout].freeze
successful_cells = cells.select { |cell| cell["disposition"] == "complete" && cell["correctness"] == true }
correct_by_task = successful_cells.group_by { |cell| cell.dig("cell", "task") }.transform_values(&:length)

require_condition(summary["assigned_cells"] == 48, "expected summary for 48 assigned cells")
require_condition(cells.length == 48, "summary does not contain all 48 cells")
require_condition(tasks.length == 2, "expected two pilot tasks")
require_condition(cells.all? { |cell| terminal_dispositions.include?(cell["disposition"]) },
                  "findings require all 48 cells to have terminal dispositions")
require_condition(review_complete?(reviews, tasks, correct_by_task), "findings require both reviews complete for every correct cell")

groups = cells.group_by { |cell| [cell.dig("cell", "task"), cell.dig("cell", "agent"), cell.dig("cell", "condition")] }
require_condition(groups.length == tasks.length * 2 * 3, "unexpected task/agent/condition group count")
groups.each do |key, members|
  tracks = members.map { |cell| cell.dig("cell", "track") }.tally
  repeats_by_track = members.group_by { |cell| cell.dig("cell", "track") }.transform_values do |track_cells|
    track_cells.map { |cell| cell.dig("cell", "repeat") }.sort
  end
  require_condition(members.length == 4 && tracks == {"natural" => 2, "specified" => 2},
                    "expected four cells per task/agent/condition group (two tracks × two repeats): #{key.join('/')}")
  require_condition(repeats_by_track.values.all? { |repeats| repeats == [1, 2] },
                    "expected repeat 1 and 2 in both tracks: #{key.join('/')}")
end

group_summaries = groups.map do |(task, agent, condition), members|
  correct_members = members.select { |cell| cell["disposition"] == "complete" && cell["correctness"] == true }
  times = members.map { |cell| cell["all_agent_execution_seconds"] }.grep(Numeric)
  changes = correct_members.map { |cell| cell.dig("solution_metrics", "production_changed_lines") }.grep(Numeric)
  [task, agent, condition, members.sum { |cell| cell["continuation_count"].to_i },
   median(changes), changes.length, median(times), times.length]
end
max_continuations = group_summaries.map { |entry| entry[3] }.max || 0
line_medians = group_summaries.map { |entry| entry[4] }.grep(Numeric)

first_turn = successful_cells.count { |cell| cell["continuation_count"] == 0 }
continuations = cells.sum { |cell| cell["continuation_count"].to_i }
terminal_counts = cells.map { |cell| cell["disposition"] }.tally
known_times = cells.map { |cell| cell["all_agent_execution_seconds"] }.grep(Numeric)
total_execution = median(known_times)

lines = [
  "# Pilot findings",
  "",
  "Descriptive findings from the 48-cell pilot after every cell has a terminal disposition and both reviews are complete for each correct cell. Failed terminal outcomes remain in the denominators; these small exploratory results do not establish a winner or support broad claims.",
  "",
  "## Completion and workflow",
  "",
  "- **First-turn correct completion:** #{first_turn}/48 cells reached a correct terminal result with zero continuation records; **eventual correctness:** #{successful_cells.length}/48 cells reached a correct terminal result. A checker-only recheck still counts as first turn.",
  "- Terminal dispositions: #{terminal_counts.sort.map { |status, count| "#{status}=#{count}" }.join(', ')}.",
  "- **Continuation records:** #{continuations} across the grid. A checker-only recheck does not count as a continuation.",
  "- Median cumulative agent execution time was #{format_seconds(total_execution)} seconds across #{known_times.length}/48 cells with a recorded numeric duration. This sums execution time across continuations where present; it excludes waiting and checker runtime.",
  "- Continuations ranged from 0 to #{max_continuations} within the four-cell task/agent/condition groups. Median production changed-line counts ranged from #{format_number(line_medians.min)} to #{format_number(line_medians.max)} across those groups.",
  "",
  "## Production changes by task and condition",
  "",
  "Each row summarizes four assigned cells for one task, agent, and condition: two repeats in each of the natural and specified tracks. First-turn counts require a correct terminal result and zero continuations. Time medians use all cells with a known numeric duration (n shown); production line medians use correct terminal cells only (n shown). Production line counts are descriptive, not simplicity scores.",
  "",
  "| Task | Agent | Recorded model | Condition | Assigned cells | Correct terminal | First-turn correct | Continuations | Median agent seconds (n known) | Median production changed lines (n correct) |",
  "|---|---|---|---|---:|---:|---:|---:|---:|---:|"
]

groups.sort.each do |(task, agent, condition), members|
  correct_members = members.select { |cell| cell["disposition"] == "complete" && cell["correctness"] == true }
  turn_count = correct_members.count { |cell| cell["continuation_count"] == 0 }
  continuation_count = members.sum { |cell| cell["continuation_count"].to_i }
  times = members.map { |cell| cell["all_agent_execution_seconds"] }.grep(Numeric)
  changes = correct_members.map { |cell| cell.dig("solution_metrics", "production_changed_lines") }.grep(Numeric)
  seconds = median(times)
  changed_lines = median(changes)
  lines << "| #{task} | #{agent} | #{MODEL_LABELS.fetch(agent, 'unknown')} | #{CONDITION_LABELS.fetch(condition, condition)} | 4 | #{correct_members.length}/4 | #{turn_count}/4 | #{continuation_count} | #{format_seconds(seconds)} (#{times.length}/4) | #{format_number(changed_lines)} (#{changes.length}/4) |"
end

lines.concat([
  "",
  "## Reading the results",
  "",
  "The table separates workflow completion from production change size. Failure rows remain visible in assigned-cell and time denominators; only correct terminal cells contribute production-line medians. A condition with more continuation records can still finish with a small patch; code-line counts do not measure design quality, and cumulative agent seconds do not include human or checker waiting. No weighted score or overall winner is calculated.",
  "",
  "The pilot uses two tasks, two repeats per task/agent/condition, and two tracks. The recorded models were Claude `claude-opus-5` and Codex `gpt-5.6-terra`; differences between agents also include their model and runtime. Treat each contrast as exploratory and task-specific.",
  "",
  "## Supporting detail",
  "",
  "- [Detailed cell comparison](comparison.md)",
  "- [Cell and artifact index](code-index.md)",
  "- [Automated review summary](review-findings-final/automated-review.md)",
  "- [Workflow example: Codex RubyPowers natural cell 0014](workflow-example-0014.md)",
  ""
])

File.write(OUTPUT_PATH, lines.join("\n"))
puts "Wrote #{OUTPUT_PATH}"
