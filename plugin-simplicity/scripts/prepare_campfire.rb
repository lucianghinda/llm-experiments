#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "tmpdir"

module CampfireSnapshot
  SOURCE_SHA = "f1aec6133667a7486d521430f871bc420e18ec2b"
  SAFETY_MODEL = "app/models/user/bot.rb"
  SAFETY_TEST = "test/controllers/messages/by_bots_controller_test.rb"

  module_function

  def git(source, *args)
    output, error, status = Open3.capture3("git", "-C", source, *args)
    raise "git #{args.first} failed: #{error}" unless status.success?
    output.strip
  end

  def prepare(source:, output_root:, expected_sha: SOURCE_SHA)
    source = File.expand_path(source)
    output_root = File.expand_path(output_root)
    actual_sha = git(source, "rev-parse", "HEAD")
    raise "expected Campfire #{expected_sha}, found #{actual_sha}" unless actual_sha == expected_sha
    raise "Campfire source tree is dirty" unless git(source, "status", "--porcelain").empty?

    feature = File.join(output_root, "fixtures", "campfire_feature")
    safety = File.join(output_root, "fixtures", "campfire_safety")
    [feature, safety].each { |path| FileUtils.rm_rf(path); FileUtils.mkdir_p(path) }
    [feature, safety].each { |path| archive(source, actual_sha, path) }

    model_path = File.join(safety, SAFETY_MODEL)
    model = File.read(model_path)
    fixed = "active_bots.find_by(id: bot_id, bot_token: bot_token)"
    planted = "active.find_by(id: bot_id, bot_token: bot_token)"
    raise "expected bot authentication line not found exactly once" unless model.scan(fixed).length == 1
    File.write(model_path, model.sub(fixed, planted))

    test_path = File.join(safety, SAFETY_TEST)
    raise "retained bot regression test missing" unless File.read(test_path).include?("create can't be abused to post messages as any user")
    raise "snapshot unexpectedly contains git history" if [feature, safety].any? { |path| File.exist?(File.join(path, ".git")) }

    {
      "source" => source,
      "source_sha" => actual_sha,
      "feature_fixture" => feature,
      "safety_fixture" => safety,
      "safety_change" => "active_bots scope reverted; regression test retained",
      "source_dirty" => false
    }
  end

  def archive(source, sha, destination)
    archive_path = File.join(Dir.tmpdir, "campfire-#{Process.pid}-#{sha}.tar")
    _out, error, status = Open3.capture3("git", "-C", source, "archive", "--format=tar", "-o", archive_path, sha)
    raise "git archive failed: #{error}" unless status.success?
    _out, error, status = Open3.capture3("tar", "-xf", archive_path, "-C", destination)
    raise "tar extraction failed: #{error}" unless status.success?
  ensure
    FileUtils.rm_f(archive_path) if archive_path
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    OptionParser.new do |parser|
      parser.banner = "Usage: ruby scripts/prepare_campfire.rb --source CHECKOUT"
      parser.on("--source PATH", "Clean Campfire source checkout at the pinned commit") { |value| options[:source] = value }
    end.parse!
    abort "--source is required" unless options[:source]
    result = CampfireSnapshot.prepare(source: options[:source], output_root: File.expand_path("..", __dir__))
    puts JSON.pretty_generate(result)
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
