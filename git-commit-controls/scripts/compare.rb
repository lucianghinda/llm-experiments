#!/usr/bin/env ruby
# frozen_string_literal: true

# Puts the host run and the clean-room container run side by side, so the
# question "did the host's own configuration change any conclusion?" is answered
# by a table rather than by assertion.
#
#   GCC_RUNS=runs           ruby scripts/measure.rb
#   GCC_RUNS=runs-container ruby scripts/measure.rb
#   ruby scripts/compare.rb

require "json"

EXP = File.expand_path("..", __dir__)

def load(name)
  path = File.join(EXP, name)
  return {} unless File.exist?(path)

  JSON.parse(File.read(path)).group_by { |r| [r["agent"], r["arm"]] }
end

host = load("METRICS.json")
cont = load("METRICS-container.json")

def cell(reps, key)
  return "-" if reps.nil? || reps.empty?

  "#{reps.count { |r| r[key] }}/#{reps.length}"
end

puts "# Host vs clean room"
puts
puts "Host runs carry the machine's own `~/.claude/CLAUDE.md` and settings as a"
puts "constant. Container runs carry no agent configuration at all."
puts
%w[claude codex opencode].each do |agent|
  arms = (host.keys + cont.keys).select { |a, _| a == agent }.map(&:last).uniq.sort
  next if arms.empty?

  puts "## #{agent}"
  puts
  puts "| arm | attribution host | attribution room | conventional host | conventional room | body host | body room |"
  puts "|---|---|---|---|---|---|---|"
  arms.each do |arm|
    h = host[[agent, arm]]
    c = cont[[agent, arm]]
    withbody = ->(reps) { reps&.map { |r| r.merge("body" => r["body_lines"].positive?) } }
    puts format("| `%s` | %s | %s | %s | %s | %s | %s |", arm,
                cell(h, "any_attribution"), cell(c, "any_attribution"),
                cell(h, "conventional"), cell(c, "conventional"),
                cell(withbody.call(h), "body"), cell(withbody.call(c), "body"))
  end
  puts
end

all_c = cont.values.flatten
puts "## Attribution text seen in the clean room"
puts
tally = all_c.map { |r| r["attribution"] }.compact.tally
puts(tally.empty? ? "(none)" : tally.sort_by { |_, n| -n }.map { |t, n| "- `#{t}` — #{n}" })
