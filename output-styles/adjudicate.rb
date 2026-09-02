#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the hand-read verdicts in ADJUDICATION.md back onto the regex scores.
#
# coverage.rb reports a FLOOR: its regexes are written in ordinary technical
# vocabulary, and several variants under test exist to replace that vocabulary,
# so an output can state a fact perfectly and still be scored as missing it.
# ADJUDICATION.md records what each regex miss scores when the output is read
# instead of matched. This script totals both numbers side by side.
#
# Usage: ruby adjudicate.rb
#
# The verdict lines in ADJUDICATION.md look like:
#   runs/run-1/04-query-object/07-style-asd.md | <fact> | PRESENT | "<quote>"
# Only the path and the verdict are read here; the quote is for the reader.

ADJ = File.join(__dir__, "ADJUDICATION.md")
abort "missing #{ADJ}" unless File.exist?(ADJ)

# The fact checklists come from the other experiment, so a cell here is scored
# by exactly the same regexes as a cell there. Its own VARIANTS map names that
# experiment's filenames and is dropped rather than redefined.
STE_COVERAGE = File.expand_path("../simplified-technical-english/coverage.rb", __dir__)
eval(File.read(STE_COVERAGE).split(/^GRAND =/).first, TOPLEVEL_BINDING, STE_COVERAGE) # rubocop:disable Security/Eval
Object.send(:remove_const, :VARIANTS)

VARIANTS = {
  "01-default" => "default",
  "02-concise" => "concise",
  "03-explanatory" => "explanatory",
  "04-learning" => "learning",
  "05-proactive" => "proactive",
  "06-style-ste" => "style:STE",
  "07-style-asd" => "style:ASD",
  "08-style-asd-hatch" => "style:ASD+hatch",
  "09-style-asd-bare" => "style:ASD bare",
  "10-prompt-ste" => "prompt:STE",
  "11-prompt-asd" => "prompt:ASD",
  "12-prompt-asd-hatch" => "prompt:ASD+hatch"
}.freeze

# Regex floors, recomputed here rather than trusted from a pasted table.
floor = Hash.new(0)
cells = Hash.new(0)
CHECKS.each do |target, checks|
  VARIANTS.each do |slug, label|
    Dir.glob(File.join(__dir__, "runs", "run-*")).sort.each do |run|
      path = File.join(run, target, "#{slug}.md")
      next unless File.exist?(path)

      text = File.read(path)
      floor[label] += checks.each_value.count { |rx| text.match?(rx) }
      cells[label] += 1
    end
  end
end

# Verdicts. A PRESENT means the regex missed a fact the output really states.
gained = Hash.new(0)
present = 0
absent = 0
File.readlines(ADJ).each do |line|
  next unless line =~ %r{^\s*(runs/\S+\.md)\s*\|\s*.+?\s*\|\s*(PRESENT|ABSENT)}

  slug = File.basename(Regexp.last_match(1), ".md")
  label = VARIANTS[slug] or next

  if Regexp.last_match(2) == "PRESENT"
    gained[label] += 1
    present += 1
  else
    absent += 1
  end
end

total = VARIANTS.values.first && cells[VARIANTS.values.first]
puts "verdicts read: #{present + absent} (#{present} PRESENT, #{absent} ABSENT)"
puts "cells per variant: #{total}, so each column is out of #{total * 6}"
puts
puts format("%-18s %9s %9s %7s", "variant", "regex", "read", "gain")
puts "-" * 46
VARIANTS.each_value do |label|
  f = floor[label]
  g = gained[label]
  puts format("%-18s %6d/%-3d %6d/%-3d %7s", label, f, cells[label] * 6, f + g, cells[label] * 6,
              g.zero? ? "-" : "+#{g}")
end
puts
puts "regex = coverage.rb floor; read = floor plus facts confirmed present by hand"
