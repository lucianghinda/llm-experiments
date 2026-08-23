#!/usr/bin/env ruby
# frozen_string_literal: true

# test-direct-type: did the agent write a test that is actually load-bearing?
#
# "A test file appeared and it is green" is not enough -- a test that asserts
# nothing is green too, and would score as a success while measuring nothing.
# So the rule is mutated out of the source and the agent's test has to go red.
#
# WHAT COUNTS AS "WROTE A TEST"
#
# A new file OR new tests appended to an existing one. The first version of this
# check only looked for an untracked *_test.rb and failed a trial where the agent
# had done the task properly: told to put the test "where tests belong", it added
# it to the existing room_test.rb, which in a conventional Rails app is the most
# idiomatic answer available. The check was wrong, not the agent.
#
# WHY THE MUTATION IS RUN AGAINST NAMED TESTS
#
# Once appending is allowed, running the whole file would run the suite's own
# pre-existing tests too -- and those already cover this rule, so the mutation
# would go red no matter what the agent wrote. The added test names are read out
# of the diff and passed to Minitest's -n filter, so the mutation is judged
# against the agent's work alone.
#
# Paths are discovered by trying both spellings rather than passed in, so the
# check needs no knowledge of which variant it is running in -- one fewer thing
# that can differ between conditions.

require "shellwords"
require_relative "../lib/acceptance"

def resolve(*candidates)
  candidates.find { |c| File.exist?(File.join(Acceptance::APP_DIR, c)) }
end

MODEL = resolve("app/models/room.rb", "platform/core/entities/room.rb")

# EVERY controller that narrows its scope, found rather than listed.
#
# The first version named rooms/opens_controller.rb alone, and that was wrong in
# a way that only a real trial could reveal: Rooms::ClosedsController carries its
# own `without_directs` scope, so an agent that tested the closeds controller had
# written a perfectly good test of a real enforcement point, and the mutation
# could not break it. The trial was scored as a failure for being right in a
# place the check was not looking.
#
# An incomplete mutation can only ever produce false FAILURES -- a test that
# survives a mutation is judged vacuous -- so it cannot have inflated any pass,
# but it silently punishes correct work, which is worse than useless.
CONTROLLER_ROOTS = ["app/controllers", "delivery/http/handlers"].freeze

def scope_narrowing_files
  root = CONTROLLER_ROOTS.find { |r| Dir.exist?(File.join(Acceptance::APP_DIR, r)) }
  return [] unless root

  Dir.glob(File.join(Acceptance::APP_DIR, root, "**", "*.rb"))
     .select { |path| File.read(path).include?("without_directs") }
     .map { |path| path.sub(Acceptance::APP_DIR + "/", "") }
end

PROMOTERS = scope_narrowing_files

new_files = Acceptance.run("git ls-files --others --exclude-standard")["out"]
                      .split("\n").map(&:strip).select { |f| f.end_with?("_test.rb") }
modified_files = Acceptance.run("git diff --name-only")["out"]
                           .split("\n").map(&:strip).select { |f| f.end_with?("_test.rb") }

touched = (new_files + modified_files).uniq

if touched.empty?
  Acceptance.report(
    [{ "label" => "a test was added", "ok" => false,
       "detail" => "no new or modified *_test.rb anywhere in the tree" }],
    "new_test_files" => [], "modified_test_files" => [], "mutation_killed" => nil
  )
end

# Rails turns `test "a name"` into the method `test_a_name`: whitespace becomes
# underscores and nothing else changes.
#
# The quote characters are matched as a MATCHED PAIR rather than as a character
# class. `["'](.+?)["']` looks equivalent and is not: it lets a double-quoted
# name terminate on an apostrophe, so `test "an administrator can't promote"`
# yielded `test_an_administrator_can`. That happened to still work as a filter,
# because Minitest's -n is an unanchored regex and the truncation was a prefix --
# but a prefix can also match several tests at once, or none, and either would
# have decided a verdict on the wrong evidence.
def added_test_methods(file)
  diff = Acceptance.run("git diff -U0 -- #{Shellwords.escape(file)}")["out"]
  names = diff.scan(/^\+\s*test\s+"([^"]+)"/).flatten
  names += diff.scan(/^\+\s*test\s+'([^']+)'/).flatten
  names = names.map { |n| "test_#{n.gsub(/\s+/, '_')}" }
  names += diff.scan(/^\+\s*def\s+(test_\w+)/).flatten
  names.uniq
end

named = modified_files.flat_map { |f| added_test_methods(f) }
# A brand new file contributes every test it holds, so it needs no filter.
filter = named.empty? || new_files.any? ? nil : "-n \"/#{named.map { |n| Regexp.escape(n) }.join('|')}/\""

command = "bin/rails test #{touched.map { |f| Shellwords.escape(f) }.join(' ')} #{filter}".strip

green = Acceptance.run(command, timeout: 900)
green_summary = green["out"][/\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?/]
ran = green_summary.to_s[/\A(\d+) runs?/, 1].to_i
# Zero tests run is not a pass. A filter that matched nothing exits green, and
# would score an agent that wrote no test at all as having written a good one.
passes_now = green["exit"].zero? && !green_summary.nil? && ran.positive?

# --- mutate -------------------------------------------------------------------
#
# Both enforcement points, because both are honest readings of the prompt: the
# model rejects the type change on save, and the controller that promotes rooms
# narrows its scope so a direct room is never in reach. An agent that tested the
# second one wrote a real test, and a mutation touching only the first would
# fail it for being right in a way the check did not anticipate.
mutation_sites = ([MODEL] + PROMOTERS).compact
originals = mutation_sites.to_h { |p| [p, File.read(File.join(Acceptance::APP_DIR, p))] }

if MODEL
  path = File.join(Acceptance::APP_DIR, MODEL)
  File.write(path, File.read(path).gsub(/^[ \t]*validate\s+:direct_rooms_keep_their_type.*\n/, ""))
end
PROMOTERS.each do |relative|
  path = File.join(Acceptance::APP_DIR, relative)
  File.write(path, File.read(path).gsub(/\.rooms\.without_directs/, ".rooms"))
end

mutated = Acceptance.run(command, timeout: 900)
mutated_summary = mutated["out"][/\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?/]
killed = !mutated["exit"].zero?

originals.each { |p, content| File.write(File.join(Acceptance::APP_DIR, p), content) }

# The agent was told to add a test and change nothing else. Whether it obeyed is
# recorded; it does not decide the verdict, because a test that is green before
# the mutation and red after it has proved the rule either way.
edited_non_test = Acceptance.run("git diff --name-only")["out"]
                            .split("\n").map(&:strip)
                            .reject { |f| f.end_with?("_test.rb") }

Acceptance.report(
  [
    { "label" => "the new test passes as written (#{green_summary || 'no summary line'})",
      "ok" => passes_now, "detail" => green["out"].lines.first(40).join },
    { "label" => "the new test fails once the rule is removed",
      "ok" => killed, "detail" => "after mutation: #{mutated_summary || 'no summary line'}" }
  ],
  "new_test_files" => new_files,
  "modified_test_files" => modified_files,
  "added_test_methods" => named,
  "command" => command,
  "mutation_killed" => killed,
  "green_summary" => green_summary,
  "mutated_summary" => mutated_summary,
  "mutation_sites" => mutation_sites,
  "edited_non_test_files" => edited_non_test
)
