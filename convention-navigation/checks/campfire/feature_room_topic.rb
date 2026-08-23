#!/usr/bin/env ruby
# frozen_string_literal: true

# feature-room-topic: did the field actually land in all four places?
#
# The acceptance test is written here rather than shipped in the repository. In
# the tree it would be a specification the agent could read, and reading it
# would replace the navigation this task exists to measure.
#
# It is deliberately written against URL helpers and model constants only, so
# the same file is valid in both variants. A check that referred to a path would
# have to differ between conditions, and a check that differs between conditions
# is not a check.
#
# Migrations are applied here rather than assumed. That is not a formality: the
# scrambled variant reads migrations from db/changes, so one written into
# db/migrate is never applied and the column never appears. Finding where
# migrations live is part of the task.

require "fileutils"
require_relative "../lib/acceptance"

ACCEPTANCE_TEST = <<~RUBY
  require "test_helper"

  class RoomTopicAcceptanceTest < ActionDispatch::IntegrationTest
    setup { sign_in :david }

    test "rooms carry a topic column" do
      assert_includes Room.column_names, "topic"
    end

    test "a room without a topic is still valid" do
      room = rooms(:hq)
      room.topic = nil
      assert room.valid?, room.errors.full_messages.to_sentence
    end

    test "a topic of 120 characters is accepted" do
      room = rooms(:hq)
      room.topic = "a" * 120
      assert room.valid?, room.errors.full_messages.to_sentence
    end

    test "a topic longer than 120 characters is rejected" do
      room = rooms(:hq)
      room.topic = "a" * 121
      assert_not room.valid?, "a 121 character topic was accepted"
    end

    test "a topic is set by the same request that renames the room" do
      room = rooms(:hq)
      put rooms_open_url(room), params: { room: { name: room.name, topic: "Deploys and incidents" } }
      assert_equal "Deploys and incidents", room.reload.topic
    end
  end
RUBY

# Where the agent put the migration, recorded before anything is applied.
#
# This is a headline observation rather than bookkeeping. The scrambled variant
# reads migrations from db/changes, so a file written into db/migrate is never
# applied and the column never appears -- and whether an agent writes to the
# conventional path anyway, in a tree where it does not work, is exactly the
# kind of thing this experiment is asking about.
migration_files = Acceptance.run("git ls-files --others --exclude-standard")["out"]
                            .split("\n").map(&:strip)
                            .select { |f| f.start_with?("db/") && f.end_with?(".rb") }
Acceptance.log "migrations written to: #{migration_files.inspect}"

migrate = Acceptance.run("bin/rails db:migrate", timeout: 600)
Acceptance.log "db:migrate exit #{migrate['exit']}"

test_path = "test/acceptance/room_topic_acceptance_test.rb"
FileUtils.mkdir_p(File.join(Acceptance::APP_DIR, File.dirname(test_path)))
File.write(File.join(Acceptance::APP_DIR, test_path), ACCEPTANCE_TEST)

result = Acceptance.run("bin/rails test #{test_path}", timeout: 900)
summary = result["out"][/\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?/]
# Exit status alone is not enough in either direction: a suite that could not
# boot exits non-zero without running anything, and a runner that matched no
# files exits zero. Require the summary line before believing either.
passed = result["exit"].zero? && !summary.nil?

# Charged separately, never folded into the verdict. A change that adds the
# field and breaks nine other tests has not done the task, but it has still
# navigated to the right places, and those are different facts.
regression = Acceptance.regression_suite

changed = Acceptance.run("git diff --name-only")["out"].split("\n").map(&:strip).reject(&:empty?)
untracked = Acceptance.run("git ls-files --others --exclude-standard")["out"]
                      .split("\n").map(&:strip).reject(&:empty?)
                      .reject { |f| f.start_with?("test/acceptance/") }

Acceptance.report(
  [
    { "label" => "topic works end to end (#{summary || 'no summary line'})",
      "ok" => passed, "detail" => result["out"].lines.first(40).join }
  ],
  "migration_files" => migration_files,
  "migration_exit" => migrate["exit"],
  "migration_output" => migrate["out"].lines.last(20).join,
  "acceptance_summary" => summary,
  "regression_suite" => regression,
  "changed_files" => changed,
  "new_files" => untracked
)
