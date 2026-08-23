# frozen_string_literal: true

# The statistics, in one place so metrics.rb and report.rb cannot drift apart.
#
# Exact tests throughout. With five repeats per cell the normal approximation to
# the Mann-Whitney U is not trustworthy, and the whole permutation set is small
# enough to enumerate: C(10,5) is 252. Nothing here estimates anything.
#
# `ruby convention-navigation/scripts/metrics.rb --selftest` exercises all of it.

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

  def u_statistic(a, b)
    r = ranks(a + b)
    r.first(a.size).sum - (a.size * (a.size + 1) / 2.0)
  end

  # Exact two-sided p: enumerate every way to split the pooled values into two
  # samples of the observed sizes and count the splits at least as extreme.
  def exact_mann_whitney(a, b)
    n1 = a.size
    n2 = b.size
    return { u: nil, p: nil, note: "empty sample" } if n1.zero? || n2.zero?

    total = n1 + n2
    combos = (1..total).reduce(1, :*) / ((1..n1).reduce(1, :*) * (1..n2).reduce(1, :*))
    return { u: u_statistic(a, b), p: nil, note: "#{combos} permutations; too many" } if combos > 200_000

    pooled = a + b
    observed = u_statistic(a, b)
    mean_u = n1 * n2 / 2.0
    deviation = (observed - mean_u).abs

    extreme = 0
    (0...total).to_a.combination(n1).each do |idx|
      set = idx.to_h { |i| [i, true] }
      left = idx.map { |i| pooled[i] }
      right = (0...total).reject { |i| set[i] }.map { |i| pooled[i] }
      extreme += 1 if (u_statistic(left, right) - mean_u).abs >= deviation - 1e-9
    end

    { u: observed, p: extreme.to_f / combos, permutations: combos }
  end

  # Two-sided exact binomial sign test. The pre-registered decision rule is about
  # DIRECTION across tasks, not about one task's p-value: a real effect should
  # push the same way on every task, and this is what says whether it did.
  def sign_test(wins, losses)
    n = wins + losses
    return { p: nil, note: "no non-tied tasks", n: 0, wins: wins } if n.zero?

    choose = ->(a, b) { (1..b).reduce(1) { |acc, i| acc * (a - b + i) / i } }
    tail = (0..n).select { |k| choose.call(n, k) <= choose.call(n, wins) }
                 .sum { |k| choose.call(n, k) }
    { p: [tail.to_f / (2**n), 1.0].min, n: n, wins: wins }
  end

  # Percentage change between two medians, guarding the zero case: a search count
  # can legitimately be 0 on one side, and "infinitely more searching" is not a
  # number to put in a table.
  def percent_change(from, to)
    return nil if from.nil? || to.nil? || from.zero?

    ((to - from) / from.to_f) * 100
  end
end
