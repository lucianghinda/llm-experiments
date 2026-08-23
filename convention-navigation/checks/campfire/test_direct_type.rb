#!/usr/bin/env ruby
# frozen_string_literal: true

# test-direct-type: did the agent write a test that is actually load-bearing?
#
# "A test file appeared and it is green" is not enough -- a test that asserts
# nothing is green too, and would score as a success while measuring nothing.
# So the rule is mutated out of the source and the agent's test has to go red.
#
# The mutation removes BOTH places the rule is enforced, because both are
# honest readings of the prompt: the model rejects the type change on save, and
# the controller that promotes rooms narrows its scope so a direct room is never
# in reach. An agent that tested the second one wrote a real test, and a
# mutation that only touched the first would fail it for being right in a way
# the check did not anticipate.
#
# Paths are discovered by trying both spellings rather than passed in. The check
# then needs no knowledge of which variant it is running in, which is one fewer
# thing that can differ between conditions.

require_relative "../lib/acceptance"

def resolve(*candidates)
  candidates.find { |c| File.exist?(File.join(Acceptance::APP_DIR, c)) }
end

MODEL = resolve("app/models/room.rb", "platform/core/entities/room.rb")
PROMOTER = resolve("app/controllers/rooms/opens_controller.rb",
                   "delivery/http/handlers/rooms/opens_controller.rb")

added = Acceptance.run("git ls-files --others --exclude-standard")["out"]
                  .split("\n").map(&:strip)
                  .select { |f| f.end_with?("_test.rb") }

if added.empty?
  Acceptance.report(
    [{ "label" => "a new test file was added", "ok" => false,
       "detail" => "no untracked *_test.rb anywhere in the tree" }],
    "added_tests" => [], "mutation_killed" => nil
  )
end

green = Acceptance.run("bin/rails test #{added.join(' ')}", timeout: 900)
green_summary = green["out"][/\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?/]
passes_now = green["exit"].zero? && !green_summary.nil?

# --- mutate -------------------------------------------------------------------
originals = [MODEL, PROMOTER].compact.to_h { |p| [p, File.read(File.join(Acceptance::APP_DIR, p))] }

if MODEL
  path = File.join(Acceptance::APP_DIR, MODEL)
  File.write(path, File.read(path).gsub(/^[ \t]*validate\s+:direct_rooms_keep_their_type.*\n/, ""))
end
if PROMOTER
  path = File.join(Acceptance::APP_DIR, PROMOTER)
  File.write(path, File.read(path).gsub(/Current\.user\.rooms\.without_directs/, "Current.user.rooms"))
end

mutated = Acceptance.run("bin/rails test #{added.join(' ')}", timeout: 900)
mutated_summary = mutated["out"][/\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?/]
killed = !mutated["exit"].zero?

originals.each { |p, content| File.write(File.join(Acceptance::APP_DIR, p), content) }

# The agent was told to add a test and change nothing else. Whether it obeyed is
# recorded; it does not decide the verdict, because a test that is green before
# the mutation and red after it has proved the rule either way.
edited = Acceptance.run("git diff --name-only")["out"].split("\n").map(&:strip).reject(&:empty?)

Acceptance.report(
  [
    { "label" => "the new test passes as written (#{green_summary || 'no summary line'})",
      "ok" => passes_now, "detail" => green["out"].lines.first(40).join },
    { "label" => "the new test fails once the rule is removed",
      "ok" => killed, "detail" => "after mutation: #{mutated_summary || 'no summary line'}" }
  ],
  "added_tests" => added,
  "mutation_killed" => killed,
  "mutated_summary" => mutated_summary,
  "mutation_sites" => [MODEL, PROMOTER].compact,
  "edited_existing_files" => edited
)
