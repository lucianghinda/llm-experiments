#!/usr/bin/env ruby
# frozen_string_literal: true

# Aggregates trial metrics and compares the conditions.
#
#   ruby convention-navigation/scripts/metrics.rb
#   ruby convention-navigation/scripts/metrics.rb --selftest
#   ruby convention-navigation/scripts/metrics.rb --include-failures
#
# Four rules this file exists to enforce.
#
# NEVER POOL ACROSS AGENTS. Claude reports structured tool calls and Codex
# reports shell commands, so "tool calls" does not mean the same thing on both
# sides of an average. A number pooled over them measures nothing.
#
# NEVER POOL ACROSS TASKS. Finding one line and adding a field across four
# layers are different amounts of work, and their token totals differ by more
# than any condition effect. Tasks are compared to themselves.
#
# ONLY SUCCESSFUL TRIALS COUNT TOWARD COST. A condition that "saves" tokens by
# giving up early has not saved anything. Failures are counted and reported
# separately, because a higher failure rate is itself a result -- and if the
# scrambled condition fails more, that supports the hypothesis more strongly
# than any token difference would.
#
# USE AN EXACT TEST. With five repeats per cell the normal approximation to the
# Mann-Whitney U is not trustworthy, and the whole permutation set is small
# enough to enumerate: C(10,5) is 252.

require "json"
require_relative "lib/stats"

METRICS = %w[
  total_input_tokens
  output_tokens
  total_tool_calls
  search_calls
  read_calls
  distinct_files_read
  tool_calls_to_first_target_read
  searches_before_first_target
  wall_seconds
].freeze

CONDITIONS = %w[conventional scrambled scrambled-mapped conventional-mapped].freeze
CONDITION_PAIRS = [
  # The comparison the experiment is for.
  %w[conventional scrambled],
  # Does writing the layout down buy the advantage back, and what does carrying
  # the map cost on every request?
  %w[scrambled scrambled-mapped],
  %w[conventional scrambled-mapped],
  # And the control for that last one. A mapped trial beating conventional says
  # nothing on its own while only mapped trials carry a document at all: this
  # pair holds the document constant and varies only what it has to tell you.
  %w[conventional conventional-mapped],
  %w[conventional-mapped scrambled-mapped]
].freeze

if ARGV.include?("--selftest")
  failures = []
  check = lambda do |label, actual, expected, tol = 1e-9|
    ok = expected.nil? ? actual.nil? : (actual - expected).abs <= tol
    puts format("  %-52s %s (got %s, want %s)", label, ok ? "ok" : "FAIL", actual.inspect, expected.inspect)
    failures << label unless ok
  end

  check.call("U for [1,2,3] vs [4,5,6]", Stats.u_statistic([1, 2, 3], [4, 5, 6]), 0.0)
  check.call("U for [4,5,6] vs [1,2,3]", Stats.u_statistic([4, 5, 6], [1, 2, 3]), 9.0)
  sep = Stats.exact_mann_whitney([1, 2, 3], [4, 5, 6])
  check.call("exact p for complete separation, n=3 vs 3", sep[:p], 0.1)
  check.call("permutations for n=3 vs 3", sep[:permutations].to_f, 20.0)
  check.call("U for all-tied samples", Stats.u_statistic([1, 1], [1, 1]), 2.0)
  check.call("exact p for all-tied samples", Stats.exact_mann_whitney([1, 1], [1, 1])[:p], 1.0)
  check.call("permutations for n=5 vs 5",
             Stats.exact_mann_whitney([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])[:permutations].to_f, 252.0)
  check.call("median of even-length sample", Stats.median([1, 2, 3, 4]), 2.5)
  check.call("median of odd-length sample", Stats.median([5, 1, 3]), 3)
  # Four tasks all pointing the same way: 2 * (1/16) = 0.125.
  check.call("sign test, 4 wins 0 losses", Stats.sign_test(4, 0)[:p], 0.125)
  check.call("sign test, 3 wins 1 loss", Stats.sign_test(3, 1)[:p], 0.625)
  check.call("sign test, 5 wins 0 losses", Stats.sign_test(5, 0)[:p], 0.0625)

  puts(failures.empty? ? "\nall self-tests passed" : "\n#{failures.size} self-test(s) FAILED")
  exit(failures.empty? ? 0 : 1)
end

include_failures = ARGV.include?("--include-failures")

EXPERIMENT_DIR = File.expand_path("..", __dir__)
# One tree, never both. results-raw/ holds every trial and results/ holds the
# published subset, which for a public app are the same files copied. A glob
# matching both counts every published trial twice -- which does not merely
# inflate n, it duplicates each observation, halves the apparent variance and
# pushes the exact p-values toward significance.
raw = Dir.glob(File.join(EXPERIMENT_DIR, "results-raw", "**", "metrics.json"))
files = raw.empty? ? Dir.glob(File.join(EXPERIMENT_DIR, "results", "**", "metrics.json")) : raw
abort "no metrics.json found. Run trials, then parse_transcript.rb --all" if files.empty?

all = files.map { |f| JSON.parse(File.read(f)) }
rows = include_failures ? all : all.select { |r| r["passed"] }

puts "#{all.size} trial(s); #{rows.size} counted#{include_failures ? '' : ' (successful only)'}\n\n"

directions = Hash.new { |h, k| h[k] = { wins: 0, losses: 0, ties: 0 } }

all.group_by { |r| r["agent"] }.sort.each do |agent, agent_rows|
  puts "=" * 80
  puts "AGENT: #{agent}"
  puts "=" * 80

  agent_rows.group_by { |r| r["task"] }.sort.each do |task, task_rows|
    counted = include_failures ? task_rows : task_rows.select { |r| r["passed"] }
    if counted.empty?
      puts "\n#{task}   (no successful trials; #{task_rows.size} attempted)"
      next
    end

    by_condition = counted.group_by { |r| r["condition"] }
    sizes = CONDITIONS.filter_map { |c| "#{c}=#{(by_condition[c] || []).size}" if by_condition[c] }

    puts "\n#{task}   (n per condition: #{sizes.join(' ')})"

    METRICS.each do |metric|
      series = CONDITIONS.to_h do |cond|
        [cond, (by_condition[cond] || []).filter_map { |r| r[metric] }.map(&:to_f)]
      end
      next if series.values.all?(&:empty?)

      puts "  #{metric}"
      series.each do |cond, values|
        next if values.empty?

        puts format("    %-17s n=%-3d median=%-11s %s",
                    cond, values.size, Stats.median(values).round(1),
                    values.map { |v| v.round(1) }.inspect)
      end

      CONDITION_PAIRS.each do |(left, right)|
        a = series[left]
        b = series[right]
        next if a.empty? || b.empty?

        result = Stats.exact_mann_whitney(a, b)
        p_text = result[:p] ? format("p=%.4f", result[:p]) : "p=#{result[:note]}"
        delta = Stats.median(b) - Stats.median(a)
        puts format("    %-17s vs %-17s U=%-6s %-14s median %+.1f",
                    left, right, result[:u], p_text, delta)

        next unless [left, right] == %w[conventional scrambled]

        bucket = directions[[agent, metric]]
        if delta.positive? then bucket[:wins] += 1
        elsif delta.negative? then bucket[:losses] += 1
        else bucket[:ties] += 1
        end
      end
    end
  end
  puts
end

# --- the pre-registered decision rule -----------------------------------------
#
# Stated before any trial ran: within one agent, the assumption is supported if
# the scrambled condition costs MORE than the conventional one in the same
# direction across tasks, and if the search counts move the same way. One task
# reaching significance on its own is not the claim; consistency across tasks
# is.
puts "=" * 80
puts "DIRECTION ACROSS TASKS: conventional -> scrambled"
puts "=" * 80
puts "A win means scrambled cost more on that task. The sign test asks whether"
puts "the tasks agree, which is the pre-registered question; the per-task"
puts "p-values above ask whether any single task separates, which is not.\n\n"

directions.sort_by { |(agent, metric), _| [agent, METRICS.index(metric).to_i] }.each do |(agent, metric), tally|
  test = Stats.sign_test(tally[:wins], tally[:losses])
  p_text = test[:p] ? format("p=%.4f", test[:p]) : test[:note]
  puts format("  %-8s %-34s scrambled higher on %d/%d task(s), %d tie(s)  %s",
              agent, metric, tally[:wins], tally[:wins] + tally[:losses], tally[:ties], p_text)
end

# --- success and abort rates --------------------------------------------------
puts "\n#{'=' * 80}"
puts "OUTCOMES (never pooled: a condition that saves tokens by failing saves nothing)"
puts "=" * 80
all.group_by { |r| [r["agent"], r["task"]] }.sort.each do |(agent, task), cell|
  parts = CONDITIONS.filter_map do |cond|
    subset = cell.select { |r| r["condition"] == cond }
    next if subset.empty?

    "#{cond}=#{subset.count { |r| r['passed'] }}/#{subset.size}"
  end
  puts format("  %-8s %-26s %s", agent, task, parts.join("  "))
end

puts "\nzero-search navigation (reached a needed file with no grep, glob or find first):"
all.group_by { |r| [r["agent"], r["task"]] }.sort.each do |(agent, task), cell|
  parts = CONDITIONS.filter_map do |cond|
    subset = cell.select { |r| r["condition"] == cond && !r["zero_search_navigation"].nil? }
    next if subset.empty?

    "#{cond}=#{subset.count { |r| r['zero_search_navigation'] }}/#{subset.size}"
  end
  puts format("  %-8s %-26s %s", agent, task, parts.join("  "))
end
