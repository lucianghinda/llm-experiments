# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../scripts/prepare_campfire"

class CampfireSnapshotTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("campfire-snapshot-test")
    @source = File.join(@root, "source")
    FileUtils.mkdir_p(@source)
    git("init", "-q", @source)
    git("-C", @source, "config", "user.name", "Test")
    git("-C", @source, "config", "user.email", "test@example.invalid")
    model = File.join(@source, CampfireSnapshot::SAFETY_MODEL)
    FileUtils.mkdir_p(File.dirname(model))
    File.write(model, "def authenticate_bot(bot_key)\n  active_bots.find_by(id: bot_id, bot_token: bot_token)\nend\n")
    test = File.join(@source, CampfireSnapshot::SAFETY_TEST)
    FileUtils.mkdir_p(File.dirname(test))
    File.write(test, "test \"create can't be abused to post messages as any user\"\n")
    git("-C", @source, "add", "-A")
    git("-C", @source, "commit", "-qm", "snapshot source")
    @sha = git("-C", @source, "rev-parse", "HEAD")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_archives_source_without_history_and_reverses_only_bot_scope
    result = CampfireSnapshot.prepare(source: @source, output_root: @root, expected_sha: @sha)
    feature_model = File.read(File.join(result.fetch("feature_fixture"), CampfireSnapshot::SAFETY_MODEL))
    safety_model = File.read(File.join(result.fetch("safety_fixture"), CampfireSnapshot::SAFETY_MODEL))
    assert_includes feature_model, "active_bots.find_by"
    assert_includes safety_model, "active.find_by"
    assert File.exist?(File.join(result.fetch("safety_fixture"), CampfireSnapshot::SAFETY_TEST))
    refute File.exist?(File.join(result.fetch("feature_fixture"), ".git"))
  end

  def test_rejects_unpinned_or_dirty_checkout
    assert_raises(RuntimeError) { CampfireSnapshot.prepare(source: @source, output_root: @root, expected_sha: "wrong") }
    File.write(File.join(@source, "dirty"), "change")
    assert_raises(RuntimeError) { CampfireSnapshot.prepare(source: @source, output_root: @root, expected_sha: @sha) }
  end

  private

  def git(*args)
    output, error, status = Open3.capture3("git", *args)
    raise error unless status.success?
    output.strip
  end
end
