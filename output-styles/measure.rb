#!/usr/bin/env ruby
# frozen_string_literal: true

# Measures prose complexity of every output in runs/.
#
# The prose stripping, the sentence splitter, the jargon list and the metrics
# are loaded from ../simplified-technical-english/measure.rb rather than copied,
# so the numbers here are comparable with that experiment's by construction: one
# ruler, not two that look alike. Only the file layout differs, so only the
# layout is re-implemented.
#
# Usage: ruby measure.rb           # every target, every run
#        ruby measure.rb 02-single-method-domain

require "json"

STE_MEASURE = File.expand_path("../simplified-technical-english/measure.rb", __dir__)

# That script prints its own tables when loaded, and iterates its own TARGETS.
# Take the definitions and none of the behaviour: read the source, drop the
# printing section, evaluate the rest. Its own VARIANTS map names the other
# experiment's filenames and is not wanted here, so it is dropped rather than
# redefined, which would only warn and keep the first definition.
source = File.read(STE_MEASURE).split(/^W = 11/).first
eval(source, TOPLEVEL_BINDING, STE_MEASURE) # rubocop:disable Security/Eval
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

W = 12

targets = ARGV.empty? ? VARIANTS && nil : ARGV
runs = Dir.glob(File.join(__dir__, "runs", "run-*")).select { |p| File.directory?(p) }.sort

target_names = Dir.glob(File.join(runs.first.to_s, "*"))
               .select { |p| File.directory?(p) }.map { |p| File.basename(p) }.sort
target_names &= targets if targets

def cell(s)
  return ".".rjust(W) unless s

  format("%5.1f (%2d%%)", s[:avg], s[:over_25_pct]).rjust(W)
end

# Cost and tokens come from the CLI's own JSON envelope, not from the prose.
def usage(path)
  return nil unless File.exist?(path)

  j = JSON.parse(File.read(path))
  u = j["usage"] || {}
  {
    cost: j["total_cost_usd"],
    output_tokens: u["output_tokens"],
    turns: j["num_turns"],
    seconds: (j["duration_ms"].to_i / 1000.0).round
  }
rescue JSON::ParserError
  nil
end

target_names.each do |target|
  puts "== #{target}"
  puts format("%-8s %s", "run", VARIANTS.values.map { |v| v.rjust(W) }.join(" "))
  puts "-" * (9 + VARIANTS.size * (W + 1))

  collected = {}
  runs.each do |run|
    row = VARIANTS.keys.map do |slug|
      path = File.join(run, target, "#{slug}.md")
      s = File.exist?(path) ? stats(path) : nil
      collected[[File.basename(run), slug]] = s
      cell(s)
    end
    puts format("%-8s %s", File.basename(run), row.join(" "))
  end

  puts
  puts format("%-8s %s", "words", VARIANTS.values.map { |v| v.rjust(W) }.join(" "))
  runs.each do |run|
    row = VARIANTS.keys.map do |slug|
      s = collected[[File.basename(run), slug]]
      (s ? "#{s[:words]}w j#{s[:jargon]}" : ".").rjust(W)
    end
    puts format("%-8s %s", File.basename(run), row.join(" "))
  end

  puts
  puts format("%-8s %s", "out tok", VARIANTS.values.map { |v| v.rjust(W) }.join(" "))
  runs.each do |run|
    row = VARIANTS.keys.map do |slug|
      u = usage(File.join(run, target, "#{slug}.json"))
      (u ? "#{u[:output_tokens]}t/#{u[:turns]}n" : ".").rjust(W)
    end
    puts format("%-8s %s", File.basename(run), row.join(" "))
  end
  puts
end

puts "avg words per sentence (share of sentences over the 25-word STE limit)"
puts "words row: prose word count, jargon-list hits as jN"
puts "out tok row: output tokens and number of assistant turns"
