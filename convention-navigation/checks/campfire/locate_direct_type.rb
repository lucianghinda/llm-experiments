#!/usr/bin/env ruby
# frozen_string_literal: true

# locate-direct-type: did the agent find where the rule lives?
#
# Success is naming the right file. The line number is recorded but does not
# decide the verdict: the rule is expressed on two lines -- the declaration that
# registers it and the method that implements it -- and both are correct
# answers, while an off-by-one in a file the agent clearly found is a formatting
# slip rather than a navigation failure. Which of the two it named is kept,
# because it is a small window onto how the agent read the file.

require_relative "../lib/acceptance"

target = Acceptance.targets.first
cited = Acceptance.cited_paths
found = cited.include?(target)

expected_lines =
  if File.exist?(File.join(Acceptance::APP_DIR, target))
    File.readlines(File.join(Acceptance::APP_DIR, target)).each_with_index
        .filter_map { |line, i| i + 1 if line.include?("direct_rooms_keep_their_type") }
  else
    []
  end

lines = Acceptance.cited_lines
dirty = Acceptance.run("git status --porcelain")["out"].strip

Acceptance.report(
  [
    { "label" => "answer names #{target}", "ok" => found,
      "detail" => "cited: #{cited.inspect}" }
  ],
  "cited_paths" => cited,
  "cited_lines" => lines,
  "expected_lines" => expected_lines,
  "line_correct" => (lines & expected_lines).any?,
  # The prompt said not to change anything. Recorded rather than enforced: a
  # stray edit says something about how the agent worked and nothing about
  # whether it found the file.
  "left_tree_dirty" => !dirty.empty?,
  "answer" => Acceptance.answer
)
