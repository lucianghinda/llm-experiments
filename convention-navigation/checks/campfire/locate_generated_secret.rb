#!/usr/bin/env ruby
# frozen_string_literal: true

# locate-generated-secret: did the agent find the file, and did it read the
# right number out of it?
#
# Two checks, both required. The number alone could be a lucky guess from a
# small range, and the file alone does not prove the agent read what it found.
#
# The number is taken as the first integer anywhere in the answer rather than
# from a strict line position. Agents narrate ("The secret is 12 characters
# long") even when told to reply with two lines, and scoring that as a miss
# would measure instruction-following, which is not the variable here.

require_relative "../lib/acceptance"

EXPECTED_LENGTH = 12

target = Acceptance.targets.first
cited = Acceptance.cited_paths
found = cited.include?(target)

reported = Acceptance.answer[/\d+/]&.to_i

expected_lines =
  if File.exist?(File.join(Acceptance::APP_DIR, target))
    File.readlines(File.join(Acceptance::APP_DIR, target)).each_with_index
        .filter_map { |line, i| i + 1 if line.include?("SecureRandom.alphanumeric") }
  else
    []
  end

lines = Acceptance.cited_lines
dirty = Acceptance.run("git status --porcelain")["out"].strip

Acceptance.report(
  [
    { "label" => "answer reports a secret length of #{EXPECTED_LENGTH}",
      "ok" => reported == EXPECTED_LENGTH,
      "detail" => "read #{reported.inspect} from the answer" },
    { "label" => "answer names #{target}", "ok" => found,
      "detail" => "cited: #{cited.inspect}" }
  ],
  "reported_length" => reported,
  "cited_paths" => cited,
  "cited_lines" => lines,
  "expected_lines" => expected_lines,
  "line_correct" => (lines & expected_lines).any?,
  "left_tree_dirty" => !dirty.empty?,
  "answer" => Acceptance.answer
)
