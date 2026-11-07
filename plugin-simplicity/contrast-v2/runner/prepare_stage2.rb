#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tmpdir"

# Builds an isolated follow-up catalog from one retained stage-1 result. This
# script prepares data only; stage-2 execution is a separate explicit command.
module ContrastV2
  module_function

  def prepare(source_trial:, catalog:, output:, stage_kind:)
    raise "stage kind must be clarification or task_extension" unless %w[clarification task_extension].include?(stage_kind)

    source = File.realpath(source_trial)
    root = File.realpath(catalog)
    destination = File.expand_path(output)
    created_here = false
    raise "output already exists" if File.exist?(destination)

    meta = read_json(File.join(source, "meta.json"))
    raise "stage-1 trial metadata missing" unless meta.is_a?(Hash)
    raise "stage-1 workspace is not stable" unless meta["workspace_stable"] == true
    raise "stage-1 snapshot restoration was not verified" unless meta["restoration_verified"] == true

    snapshot = read_json(File.join(source, "snapshot.json"))
    raise "stage-1 snapshot metadata missing" unless snapshot.is_a?(Hash) && snapshot["final"]
    verify_snapshot!(source, snapshot)

    original_tasks = read_json(File.join(root, "tasks.json"))
    original_conditions = read_json(File.join(root, "conditions.json"))
    task = original_tasks.find { |entry| entry["id"] == meta.fetch("task") }
    raise "task missing from original catalog" unless task
    followup = task["followup"]
    raise "task has no follow-up prompt or checks" unless followup.is_a?(Hash)
    raise "track missing from stage-1 metadata" unless %w[natural specified].include?(meta["track"])
    condition = original_conditions.find { |entry| entry["id"] == meta.fetch("condition") }
    raise "condition missing from original catalog" unless condition

    task_fixture = File.expand_path(task.fetch("fixture"), root)
    raise "original task fixture missing" unless Dir.exist?(task_fixture)
    prompt_path = File.expand_path(followup.fetch("prompt"), root)
    raise "follow-up prompt missing" unless File.file?(prompt_path)
    initial_contract_path = File.expand_path(task.fetch("prompt").fetch("specified"), root)
    raise "specified initial prompt missing" unless File.file?(initial_contract_path)
    raw_followup_prompt = File.read(prompt_path)
    initial_contract = File.read(initial_contract_path)
    stage2_prompt, prompt_context = if stage_kind == "task_extension"
      contract_text = initial_contract.sub(/\r?\n*\z/, "")
      ["Existing required behavior\n#{contract_text}\n\nNew request\n#{raw_followup_prompt}", "specified_initial_contract_plus_followup"]
    else
      [raw_followup_prompt, "followup_only"]
    end
    checks_dir = File.join(root, "checks")
    raise "original checks directory missing" unless Dir.exist?(checks_dir)

    outcome = stage1_outcome(meta, source)
    disposition = read_json(File.join(source, "disposition.json")) rescue nil
    FileUtils.mkdir_p(destination)
    created_here = true
    fixture_relative = File.join("fixtures", task.fetch("id"))
    fixture_destination = File.join(destination, fixture_relative)
    FileUtils.mkdir_p(File.dirname(fixture_destination))
    restore_snapshot(source, fixture_destination)
    FileUtils.rm_rf(File.join(fixture_destination, ".git"))
    restore_original_visible_tests(task_fixture, fixture_destination)

    prompt_relative = File.join("prompts", task.fetch("id"), "followup.txt")
    prompt_destination = File.join(destination, prompt_relative)
    FileUtils.mkdir_p(File.dirname(prompt_destination))
    File.write(prompt_destination, stage2_prompt)
    FileUtils.cp_r(checks_dir, destination)

    staged_task = task.reject { |key, _| key == "blocked" }
    staged_task["fixture"] = fixture_relative
    staged_task["prompt"] = {"natural" => prompt_relative, "specified" => prompt_relative}
    staged_task["checks"] = Array(task.fetch("checks")) + Array(followup.fetch("checks"))
    staged_task.delete("followup")
    File.write(File.join(destination, "tasks.json"), JSON.pretty_generate([staged_task]) + "\n")
    File.write(File.join(destination, "conditions.json"), JSON.pretty_generate(original_conditions) + "\n")

    manifest = {
      "stage" => 2,
      "stage_kind" => stage_kind,
      "stage_timeout_seconds" => 900,
      "task" => meta.fetch("task"),
      "agent" => meta.fetch("agent"),
      "model" => meta["model"],
      "track" => meta.fetch("track"),
      "condition" => meta.fetch("condition"),
      "repeat" => meta["repeat"],
      "stage1_source_trial" => source,
      "stage1_outcome" => outcome,
      "stage1_status" => meta["status"],
      "stage1_disposition_category" => disposition.is_a?(Hash) ? disposition["category"] : nil,
      "stage1_final" => snapshot.fetch("final"),
      "stage1_final_bundle_sha256" => Digest::SHA256.file(File.join(source, "final.bundle")).hexdigest,
      "followup_prompt_sha256" => Digest::SHA256.file(prompt_path).hexdigest,
      "initial_contract_sha256" => Digest::SHA256.file(initial_contract_path).hexdigest,
      "stage2_prompt_sha256" => Digest::SHA256.hexdigest(stage2_prompt),
      "prompt_context" => prompt_context,
      "fixture" => fixture_relative,
      "check_count" => staged_task["checks"].length,
      "source_trial_key_note" => "stage1_source_trial is intentionally distinct from source_trial; this is an independent stage-2 assignment, not a continuation."
    }
    File.write(File.join(destination, "stage2-manifest.json"), JSON.pretty_generate(manifest) + "\n")
    manifest
  rescue StandardError
    FileUtils.rm_rf(destination) if created_here && destination && File.directory?(destination)
    raise
  end

  def read_json(path)
    JSON.parse(File.read(path))
  end

  def verify_snapshot!(source, snapshot)
    %w[baseline final].each do |version|
      bundle = File.join(source, "#{version}.bundle")
      raise "stage-1 #{version} bundle missing" unless File.file?(bundle)
      expected = snapshot.fetch(version)
      actual, error, status = Open3.capture3("git", "bundle", "list-heads", bundle)
      raise "cannot inspect stage-1 #{version} bundle: #{error}" unless status.success?
      raise "stage-1 #{version} bundle revision mismatch" unless actual.lines.any? { |line| line.split.first == expected }
    end
    raise "stage-1 snapshot failed restoration verification" unless require_pilot.verify_restore(source)
  end

  def require_pilot
    require_relative "support/harness"
    Pilot
  end

  def restore_snapshot(source, destination)
    require_pilot.restore(source, destination)
  end

  def restore_original_visible_tests(original_fixture, stage_fixture)
    %w[test test_support.rb].each do |name|
      original = File.join(original_fixture, name)
      next unless File.exist?(original)

      target = File.join(stage_fixture, name)
      FileUtils.rm_rf(target)
      FileUtils.cp_r(original, target)
    end
  end

  def stage1_outcome(meta, source)
    disposition = read_json(File.join(source, "disposition.json")) rescue nil
    return "failed" if disposition.is_a?(Hash) && disposition["category"] == "task_failure"
    return "failed" if meta["checks_passed"] == false || meta["status"] == "task_failure"

    checks = read_json(File.join(source, "checks.json")) rescue nil
    return "failed" if checks.is_a?(Array) && checks.any? { |check| check["exit"] != 0 || check["timed_out"] }
    return "passed" if meta["status"] == "complete" && meta["checks_passed"] == true &&
      checks.is_a?(Array) && !checks.empty? && checks.all? { |check| check["exit"] == 0 && check["timed_out"] != true }

    "unknown"
  end

  def cli
    options = {}
    OptionParser.new do |parser|
      %w[source-trial catalog output stage-kind].each do |key|
        parser.on("--#{key} VALUE") { |value| options[key.tr("-", "_")] = value }
      end
    end.parse!
    raise "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
    %w[source_trial catalog output stage_kind].each { |key| raise "--#{key.tr('_', '-')} required" if options[key].to_s.empty? }
    puts JSON.pretty_generate(prepare(**options.transform_keys(&:to_sym)))
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    require "open3"
    ContrastV2.cli
  rescue StandardError => error
    warn "#{error.class}: #{error.message}"
    exit 2
  end
end
