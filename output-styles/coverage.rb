#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks which non-obvious facts about each target survive each output style.
#
# The four checklists are loaded from
# ../simplified-technical-english/coverage.rb rather than copied, so a cell here
# is scored by exactly the same regexes as a cell there. Only the file layout
# differs, so only the layout is re-implemented.
#
# READ THIS BEFORE QUOTING A NUMBER. These regexes are written from the
# vocabulary of ordinary technical prose, and several variants under test exist
# to replace that vocabulary. The checker therefore marks an output down for
# obeying the instruction being measured. Every number this prints is a FLOOR,
# and a floor that sits lower for the instructed arms than for the control.
# ADJUDICATION.md in the other experiment is the worked demonstration: one cell
# published as 2 of 6 contained all six when read. Use adjudicate.rb to see the
# misses, and report both numbers.
#
# Usage: ruby coverage.rb
#        ruby coverage.rb --misses          # list what each cell failed to match

require "json"

STE_COVERAGE = File.expand_path("../simplified-technical-english/coverage.rb", __dir__)

# Take the CHECKS table and none of the printing.
source = File.read(STE_COVERAGE).split(/^GRAND =/).first
eval(source, TOPLEVEL_BINDING, STE_COVERAGE) # rubocop:disable Security/Eval
Object.send(:remove_const, :VARIANTS)

VARIANTS = {
  "01-default" => "default",
  "02-concise" => "concise",
  "03-explanatory" => "explan",
  "04-learning" => "learn",
  "05-proactive" => "proact",
  "06-style-ste" => "s:STE",
  "07-style-asd" => "s:ASD",
  "08-style-asd-hatch" => "s:ASDw",
  "09-style-asd-bare" => "s:bare",
  "10-prompt-ste" => "p:STE",
  "11-prompt-asd" => "p:ASD",
  "12-prompt-asd-hatch" => "p:ASDw"
}.freeze

show_misses = ARGV.include?("--misses")
W = 8

runs = Dir.glob(File.join(__dir__, "runs", "run-*")).select { |p| File.directory?(p) }.sort
grand = Hash.new { |h, k| h[k] = Hash.new(0) }

CHECKS.each do |target, checks|
  next unless runs.any? { |r| File.directory?(File.join(r, target)) }

  puts "== #{target}  (#{checks.size} facts per cell)"
  puts format("%-8s %s", "run", VARIANTS.values.map { |v| v.rjust(W) }.join(" "))
  puts "-" * (9 + VARIANTS.size * (W + 1))

  runs.each do |run|
    run_name = File.basename(run)
    scores = {}

    VARIANTS.each do |slug, label|
      path = File.join(run, target, "#{slug}.md")
      next unless File.exist?(path)

      text = File.read(path)
      scores[label] = checks.each_value.count { |pattern| text.match?(pattern) }
      grand[run_name][label] += scores[label]
    end

    cells = VARIANTS.values.map { |v| (scores.key?(v) ? scores[v].to_s : ".").rjust(W) }
    puts format("%-8s %s", run_name, cells.join(" "))
  end
  puts

  next unless show_misses

  runs.each do |run|
    VARIANTS.each do |slug, label|
      path = File.join(run, target, "#{slug}.md")
      next unless File.exist?(path)

      text = File.read(path)
      missed = checks.reject { |_fact, pattern| text.match?(pattern) }.keys
      puts "  #{File.basename(run)} #{label}: MISSED #{missed.join('; ')}" if missed.any?
    end
  end
  puts if show_misses
end

puts "== totals across all four targets (out of 24)"
puts format("%-8s %s", "run", VARIANTS.values.map { |v| v.rjust(W) }.join(" "))
puts "-" * (9 + VARIANTS.size * (W + 1))
grand.each do |run_name, totals|
  cells = VARIANTS.values.map { |v| (totals.key?(v) ? totals[v].to_s : ".").rjust(W) }
  puts format("%-8s %s", run_name, cells.join(" "))
end
puts
puts "Regex floors, not verdicts. Re-read every miss by hand before quoting."
