#!/usr/bin/env ruby
# frozen_string_literal: true

# Aggregates trial metrics and compares the conditions pairwise.
#
#   ruby at-file-mentions/scripts/metrics.rb
#   ruby at-file-mentions/scripts/metrics.rb --selftest
#
# Two rules this file exists to enforce:
#
# Never pool across agents or apps. Claude and Codex do not count tool calls the
# same way, and campfire and bookmarks are different sizes of haystack. A number
# averaged over those is not a measurement of anything.
#
# Use an exact test. With five bugs per cell the normal approximation to the
# Mann-Whitney U is not trustworthy, and the whole permutation set is small
# enough to enumerate: C(10,5) is 252.

require "json"

METRICS = %w[
  wall_seconds
  output_tokens
  input_tokens
  cache_creation_input_tokens
  total_tool_calls
  context_before_first_tool_call
  tool_calls_to_first_defect_read
].freeze

CONDITIONS = %w[none bare at bare_noline at_noline].freeze
# bare vs at is the inert pair kept for the record; bare_noline vs at_noline
# is the one where the mention actually resolves. bare vs bare_noline isolates
# what the line suffix alone is worth.
# none vs bare_noline is "is handing over the path worth anything at all",
# which is the only one of these that is not about the @ at all. It was missing
# while the grid still ran five conditions, because none vs bare covered it -
# but bare is no longer run, so that pair is stuck at n=1 and this one carries
# the question now.
CONDITION_PAIRS = [%w[none bare], %w[bare at], %w[none at],
                   %w[bare_noline at_noline], %w[none at_noline],
                   %w[none bare_noline],
                   %w[bare bare_noline], %w[at at_noline]].freeze

module Stats
  module_function

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  # Mid-ranks, so ties do not silently inflate the statistic.
  def ranks(values)
    indexed = values.each_with_index.sort_by { |v, _| v }
    result = Array.new(values.size)
    i = 0
    while i < indexed.size
      j = i
      j += 1 while j + 1 < indexed.size && indexed[j + 1][0] == indexed[i][0]
      mid = ((i + 1) + (j + 1)) / 2.0
      (i..j).each { |k| result[indexed[k][1]] = mid }
      i = j + 1
    end
    result
  end

  # U for sample a against sample b.
  def u_statistic(a, b)
    all = a + b
    r = ranks(all)
    rank_sum_a = r.first(a.size).sum
    rank_sum_a - (a.size * (a.size + 1) / 2.0)
  end

  # Exact two-sided p: enumerate every way to split the pooled values into two
  # samples of the observed sizes and count the splits at least as extreme.
  def exact_mann_whitney(a, b)
    n1 = a.size
    n2 = b.size
    return { u: nil, p: nil, note: "empty sample" } if n1.zero? || n2.zero?

    total = n1 + n2
    combos = (1..total).reduce(1, :*) / ((1..n1).reduce(1, :*) * (1..n2).reduce(1, :*))
    if combos > 200_000
      return { u: u_statistic(a, b), p: nil, note: "#{combos} permutations; too many to enumerate" }
    end

    pooled = a + b
    observed = u_statistic(a, b)
    mean_u = n1 * n2 / 2.0
    observed_deviation = (observed - mean_u).abs

    at_least_as_extreme = 0
    (0...total).to_a.combination(n1).each do |idx|
      set = idx.to_h { |i| [i, true] }
      left = idx.map { |i| pooled[i] }
      right = (0...total).reject { |i| set[i] }.map { |i| pooled[i] }
      at_least_as_extreme += 1 if (u_statistic(left, right) - mean_u).abs >= observed_deviation - 1e-9
    end

    { u: observed, p: at_least_as_extreme.to_f / combos, permutations: combos }
  end
end

if ARGV.include?("--selftest")
  failures = []

  check = lambda do |label, actual, expected, tolerance = 1e-9|
    ok = expected.nil? ? actual.nil? : (actual - expected).abs <= tolerance
    puts format("  %-52s %s (got %s, want %s)", label, ok ? "ok" : "FAIL", actual.inspect, expected.inspect)
    failures << label unless ok
  end

  # Complete separation: every value of a is below every value of b, so U is 0.
  check.call("U for [1,2,3] vs [4,5,6]", Stats.u_statistic([1, 2, 3], [4, 5, 6]), 0.0)
  # The reverse is the maximum, n1*n2.
  check.call("U for [4,5,6] vs [1,2,3]", Stats.u_statistic([4, 5, 6], [1, 2, 3]), 9.0)
  # Only 1 of the 20 splits is that extreme in each direction: 2/20 = 0.1.
  sep = Stats.exact_mann_whitney([1, 2, 3], [4, 5, 6])
  check.call("exact p for complete separation, n=3 vs 3", sep[:p], 0.1)
  check.call("permutations counted for n=3 vs 3", sep[:permutations].to_f, 20.0)
  # All ties: every pair contributes 0.5, so U is half of n1*n2 and p is 1.
  check.call("U for all-tied samples", Stats.u_statistic([1, 1], [1, 1]), 2.0)
  check.call("exact p for all-tied samples", Stats.exact_mann_whitney([1, 1], [1, 1])[:p], 1.0)
  # Interleaved: 3>2, 5>2, 5>4.
  check.call("U for [1,3,5] vs [2,4,6]", Stats.u_statistic([1, 3, 5], [2, 4, 6]), 3.0)
  # The size the design actually uses.
  check.call("permutations for n=5 vs 5",
             Stats.exact_mann_whitney([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])[:permutations].to_f, 252.0)
  check.call("median of even-length sample", Stats.median([1, 2, 3, 4]), 2.5)
  check.call("median of odd-length sample", Stats.median([5, 1, 3]), 3)

  puts(failures.empty? ? "\nall self-tests passed" : "\n#{failures.size} self-test(s) FAILED")
  exit(failures.empty? ? 0 : 1)
end

EXPERIMENT_DIR = File.expand_path("..", __dir__)
# One tree, never both. results-raw/ holds every trial; results/ holds the
# published subset, and for a public app those are the same files copied. The
# glob "results*" matched both, so every published trial was counted twice --
# which does not merely inflate n, it duplicates each observation, halves the
# apparent variance and pushes the exact p-values toward significance. Prefer
# the raw tree, which is always complete, and fall back to the published one
# so a fresh clone without results-raw/ still computes.
raw = Dir.glob(File.join(EXPERIMENT_DIR, "results-raw", "**", "metrics.json"))
files = raw.empty? ? Dir.glob(File.join(EXPERIMENT_DIR, "results", "**", "metrics.json")) : raw
if files.empty?
  abort "no metrics.json found. Run trials, then parse_transcript.rb --all"
end

rows = files.map { |f| JSON.parse(File.read(f)) }
             .reject { |r| r["bug_reproduces"] == false }

puts "#{rows.size} trial(s) from #{files.size} file(s)\n\n"

grouped = rows.group_by { |r| [r["app"], r["agent"]] }

grouped.sort_by { |(app, agent), _| [app.to_s, agent.to_s] }.each do |(app, agent), cell|
  by_condition = cell.group_by { |r| r["condition"] }
  puts "=" * 78
  puts "#{app} / #{agent}   (n per condition: #{CONDITIONS.map { |c| "#{c}=#{(by_condition[c] || []).size}" }.join(' ')})"
  puts "=" * 78

  METRICS.each do |metric|
    series = CONDITIONS.to_h do |cond|
      [cond, (by_condition[cond] || []).filter_map { |r| r[metric] }.map(&:to_f)]
    end
    next if series.values.all?(&:empty?)

    puts "\n  #{metric}"
    series.each do |cond, values|
      next if values.empty?

      puts format("    %-5s n=%-3d median=%-12s values=%s",
                  cond, values.size, Stats.median(values).round(2), values.map { |v| v.round(1) }.inspect)
    end

    CONDITION_PAIRS.each do |(left, right)|
      a = series[left]
      b = series[right]
      next if a.empty? || b.empty?

      result = Stats.exact_mann_whitney(a, b)
      p_text = result[:p] ? format("p=%.4f", result[:p]) : "p=#{result[:note]}"
      delta = Stats.median(b) - Stats.median(a)
      puts format("    %-5s vs %-5s  U=%-7s %-16s median change %+.2f",
                  left, right, result[:u], p_text, delta)
    end
  end
  puts
end

puts "\nfix_verified by condition (not pooled):"
grouped.sort_by { |(app, agent), _| [app.to_s, agent.to_s] }.each do |(app, agent), cell|
  parts = CONDITIONS.map do |cond|
    subset = cell.select { |r| r["condition"] == cond }
    next "#{cond}=-" if subset.empty?

    "#{cond}=#{subset.count { |r| r['fix_verified'] }}/#{subset.size}"
  end
  puts format("  %-18s %-8s %s", app, agent, parts.join("  "))
end
