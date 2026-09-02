#!/usr/bin/env ruby
# frozen_string_literal: true

# Asserts the properties every cell has to have for the grid to mean anything,
# and exits non-zero if any of them is broken. A contaminated or half-finished
# run must not be able to pass as a clean one just because the tables render.
#
# Usage: ruby verify.rb
#
# Checked per cell:
#   - the session ended as a successful result, not an error
#   - zero MCP servers and zero slash commands reached it (clean room)
#   - the model is the same one everywhere (a mid-grid model change would make
#     the columns incomparable, which is exactly what run 3 of the other
#     experiment had to work around)
#   - the CLI version is the same one everywhere
#   - the app SHA is the one PROMPTS.md records
#   - the prompt actually carries the style words the variant is supposed to
#     carry, and carries none it should not
#
# The last one is the important one. An unknown outputStyle silently falls back
# to Default, so a mislabelled cell looks like a null result. trial.rb guards
# the custom styles by matching frontmatter; this guards the prompt arms.

require "json"

EXPECTED_SHA = {
  "01-rails-concern" => "63f4ff5698a9459f17e03663aaa9349b4b27b51b",
  "02-single-method-domain" => "9535f1eb2d9460a1766c5060383e6cb1585c749b",
  "03-single-method-algorithm" => "9535f1eb2d9460a1766c5060383e6cb1585c749b",
  "04-query-object" => "9535f1eb2d9460a1766c5060383e6cb1585c749b"
}.freeze

# Style words that must appear in the prompt, per variant. Variants 1-9 put
# nothing in the prompt at all: the style arrives through the setting.
PROMPT_WORDS = {
  "10-prompt-ste" => "in Simple Technical English",
  "11-prompt-asd" => "in ASD-STE100 Simplified Technical English",
  "12-prompt-asd-hatch" => "Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning."
}.freeze

STYLE_NAMES = {
  "02-concise" => "Concise",
  "03-explanatory" => "Explanatory",
  "04-learning" => "Learning",
  "05-proactive" => "Proactive",
  "06-style-ste" => "Simple Technical English",
  "07-style-asd" => "ASD-STE100",
  "08-style-asd-hatch" => "ASD-STE100 escape hatch",
  "09-style-asd-bare" => "ASD-STE100 bare"
}.freeze

problems = []
models = Hash.new(0)
versions = Hash.new(0)
cells = 0

Dir.glob(File.join(__dir__, "runs", "run-*", "*", "*.meta.json")).sort.each do |meta_path|
  cells += 1
  slug = File.basename(meta_path, ".meta.json")
  target = File.basename(File.dirname(meta_path))
  run = File.basename(File.dirname(File.dirname(meta_path)))
  where = "#{run}/#{target}/#{slug}"

  meta = JSON.parse(File.read(meta_path))
  result_path = meta_path.sub(".meta.json", ".json")
  unless File.exist?(result_path)
    problems << "#{where}: no result JSON"
    next
  end
  res = JSON.parse(File.read(result_path))

  problems << "#{where}: is_error" if res["is_error"]
  problems << "#{where}: subtype #{res['subtype']}" unless res["subtype"] == "success"
  problems << "#{where}: #{(res['mcp_servers'] || []).size} MCP servers" unless (res["mcp_servers"] || []).empty?
  problems << "#{where}: slash commands present" unless (res["slash_commands"] || []).empty?

  (res["modelUsage"] || {}).each_key { |m| models[m] += 1 }
  versions[meta["claude_version"]] += 1

  expected = EXPECTED_SHA[target]
  problems << "#{where}: app SHA #{meta['app_sha']}" if expected && meta["app_sha"] != expected

  # Style delivery: the setting and the prompt must each carry exactly what
  # this variant is defined to carry.
  problems << "#{where}: style_name #{meta['style_name'].inspect}" if meta["style_name"] != STYLE_NAMES[slug]

  prompt = meta["prompt"].to_s
  want = PROMPT_WORDS[slug]
  if want
    problems << "#{where}: prompt missing #{want.inspect}" unless prompt.include?(want)
  elsif prompt.match?(/Simple Technical English|ASD-STE100/)
    problems << "#{where}: prompt carries style words it should not"
  end
end

puts "cells checked: #{cells}"
puts "models:   #{models.map { |m, n| "#{m} x#{n}" }.join(', ')}"
puts "versions: #{versions.map { |v, n| "#{v} x#{n}" }.join(', ')}"
problems << "more than one model across the grid" if models.size > 1
problems << "more than one CLI version across the grid" if versions.size > 1

if problems.empty?
  puts "OK: every cell clean and consistent"
  exit 0
end

puts
puts "PROBLEMS (#{problems.size}):"
problems.each { |p| puts "  #{p}" }
exit 1
