#!/usr/bin/env ruby
# frozen_string_literal: true

# Aggregates METRICS.json into per-arm rates. Every number quoted in README.md
# comes from here, so nothing in the write-up is typed by hand.
#
#   ruby measure.rb && ruby report.rb

require "json"

EXP = File.expand_path("..", __dir__)
SUFFIX = ENV.fetch("GCC_RUNS", "runs") == "runs" ? "" : "-container"
rows = JSON.parse(File.read(File.join(EXP, "METRICS#{SUFFIX}.json")))

def rate(reps, key)
  n = reps.length
  k = reps.count { |r| r[key] }
  "#{k}/#{n}"
end

ORDER = %w[claude codex opencode].freeze

puts "# Results"
puts
ORDER.each do |agent|
  arms = rows.select { |r| r["agent"] == agent }.group_by { |r| r["arm"] }
  next if arms.empty?
  puts "## #{agent}"
  puts
  puts "| arm | n | attribution | conventional | has body | mentions AI | median subject len |"
  puts "|---|---|---|---|---|---|---|"
  arms.each do |arm, reps|
    lens = reps.map { |r| r["subject_len"] }.sort
    median = lens.length.odd? ? lens[lens.length / 2] : ((lens[lens.length / 2 - 1] + lens[lens.length / 2]) / 2.0).round
    puts format("| `%s` | %d | %s | %s | %s | %s | %s |",
                arm, reps.length,
                rate(reps, "any_attribution"),
                rate(reps, "conventional"),
                rate(reps.map { |r| r.merge("body" => r["body_lines"].positive?) }, "body"),
                rate(reps, "mentions_ai"),
                median)
  end
  puts
end

puts "## Attribution text actually produced"
puts
seen = rows.map { |r| r["attribution"] }.compact.tally
if seen.empty?
  puts "(none)"
else
  seen.sort_by { |_, n| -n }.each { |text, n| puts "- `#{text}` — #{n} time(s)" }
end
puts
puts "## Trials that failed to commit"
bad = rows.reject { |r| r["committed"] }
puts(bad.empty? ? "(none)" : bad.map { |r| "- #{r['agent']}/#{r['arm']} rep #{r['rep']}" })
