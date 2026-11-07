#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require "time"
require_relative "report"
require_relative "structure"

module GridSummary
  module_function

  DISPOSITIONS = %w[complete task_failure agent_failure infrastructure_failure timeout awaiting_review running unstarted identity_mismatch fake].freeze
  STRUCTURAL_FIELDS = %w[ruby_files classes modules method_definitions branch_nodes].freeze
  RECORDED_STATUSES = %w[complete awaiting_review task_failure agent_failure infrastructure_failure setup_failure timeout running fake_complete].freeze

  def build(results_root)
    root = File.realpath(results_root)
    @grid_root = root
    grid_path = File.join(root, "grid.json")
    raise "grid.json missing: #{grid_path}" unless File.file?(grid_path)

    grid = JSON.parse(File.read(grid_path))
    cells = grid.fetch("cells")
    options = grid.fetch("options", {})
    raise "grid cells must be an array" unless cells.is_a?(Array)

    records = validate_unique_cells(cells).map do |cell, index, identity_errors|
      summarize_cell(root, cell, index, options, identity_errors)
    end

    {
      "assigned_cells" => records.length,
      "disposition_counts" => disposition_counts(records),
      "cells" => records,
      "groups" => grouped_summaries(records),
      "analysis_note" => "Descriptive pilot evidence only. Small repetition counts do not support a universal winner or statistical inference. Structural counts and line counts are diagnostics, not simplicity scores.",
      "recorded_wall_time_note" => "Recorded wall seconds span the first started_at through the last recorded finished_at in the chain. They include setup, checks, and evaluator waits. Pending chains stop at the last recorded turn; this is not all attributable to the agent or treatment."
    }
  rescue JSON::ParserError => error
    raise "invalid grid JSON: #{error.message}"
  end

  def validate_unique_cells(cells)
    seen = Hash.new { |hash, key| hash[key] = [] }
    normalized = cells.each_with_index.map do |cell, index|
      raise "grid cell #{index + 1} is not an object" unless cell.is_a?(Hash)
      required = %w[task agent track condition repeat]
      missing = required.reject { |key| cell.key?(key) }
      raise "grid cell #{index + 1} missing identity fields: #{missing.join(", ")}" unless missing.empty?

      key = required.map { |field| cell[field] }
      seen[key] << index
      [cell, index, []]
    end
    seen.each_value do |indices|
      next if indices.length == 1

      indices.each { |index| normalized[index][2] << "duplicate assigned cell identity" }
    end
    normalized
  end

  def summarize_cell(root, cell, index, options, identity_errors)
    cell_path = File.join(root, format("%04d", index + 1))
    unless File.exist?(cell_path)
      record = cell_record(cell, index, [], "unstarted", "unknown", nil, identity_errors, absent_retention)
      return record.merge(recheck_info(cell_path, nil))
    end

    nodes, chain_note = read_chain(cell_path)
    if nodes.empty?
      disposition = chain_note.to_s.start_with?("invalid metadata") ? "infrastructure_failure" : "running"
      record = cell_record(cell, index, nodes, disposition, "unknown", nil, identity_errors, retention(nodes, nil), chain_note)
      return record.merge(recheck_info(cell_path, nil))
    end

    identity_errors = identity_errors + identity_errors_for(cell, nodes, options)
    final = nodes.last
    correctness = correctness_for(final)
    correctness = "unknown" unless identity_errors.empty?
    disposition = disposition_for(final, correctness)
    if chain_note.to_s.match?(/multiple continuations|continuation cycle/)
      correctness = "unknown"
      disposition = "awaiting_review"
    end
    disposition = "identity_mismatch" unless identity_errors.empty?
    metrics = correctness == true && identity_errors.empty? ? solution_metrics(nodes.first, final) : unknown_metrics

    cell_record(cell, index, nodes, disposition, correctness, final, identity_errors, retention(nodes, final), chain_note)
      .merge("solution_metrics" => metrics)
      .merge(recheck_info(cell_path, final[:meta]))
  end

  def read_chain(start_path)
    nodes = []
    current = start_path
    seen = {}
    note = nil
    loop do
      path = File.realpath(current)
      if seen[path]
        note = "continuation cycle"
        break
      end
      seen[path] = true
      meta_path = File.join(path, "meta.json")
      unless File.file?(meta_path)
        note = "metadata missing"
        break
      end
      meta = read_json(meta_path)
      unless meta.is_a?(Hash) && RECORDED_STATUSES.include?(meta["status"])
        note = "invalid metadata: status is missing or unrecognized"
        break
      end

      node = {path: path, relative: nil, meta: meta, snapshot: read_json(File.join(path, "snapshot.json")) || {}, checks: read_json(File.join(path, "checks.json")), incident: read_json(File.join(path, "incident.json"))}
      nodes << node
      break unless meta["status"] == "awaiting_review"

      children = matching_children(start_path, path)
      if children.length != 1
        note = children.empty? ? "awaiting_review: no continuation recorded" : "awaiting_review: multiple continuations recorded"
        break
      end
      current = children.first
    end
    [nodes, note]
  rescue Errno::ENOENT
    [nodes, "runtime record disappeared while reading"]
  end

  def matching_children(cell_root, parent)
    Dir.glob(File.join(cell_root, "continuations", "*", "meta.json")).filter_map do |meta_path|
      child = read_json(meta_path)
      next unless child.is_a?(Hash) && child["source_trial"].is_a?(String)
      source = File.realpath(child["source_trial"]) if File.exist?(child["source_trial"])
      File.dirname(meta_path) if source == parent
    end
  end

  def identity_errors_for(cell, nodes, options)
    expected = cell.slice("task", "agent", "track", "condition")
    model_key = "#{cell["agent"]}_model"
    expected_model = options[model_key]
    errors = []
    nodes.each do |node|
      meta = node[:meta]
      expected.each { |field, value| errors << "#{node[:relative] || "trial"} #{field} mismatch" unless meta[field] == value }
      errors << "model mismatch" if expected_model && meta["model"] != expected_model
    end
    errors.uniq
  end

  def correctness_for(node)
    return "unknown" unless node

    meta = node[:meta]
    checks = node[:checks]
    status = meta["status"].to_s
    return false if status == "task_failure"
    if status == "awaiting_review"
      return false if reviewed_task_failure?(node)

      return "unknown"
    end
    return false if checks.is_a?(Array) && checks.any? { |check| check.is_a?(Hash) && (check["exit"] != 0 || check["timed_out"] == true) }
    return false if status == "complete" && meta["checks_passed"] == false
    return true if meta["status"] == "complete" && meta["checks_passed"] == true && passing_checks?(checks) && meta["restoration_verified"] == true

    "unknown"
  end

  def disposition_for(node, correctness)
    meta = node[:meta]
    status = meta["status"].to_s
    return "infrastructure_failure" if (node[:incident].is_a?(Hash) && node[:incident]["eligible_behavioral_trial"] == false) || %w[infrastructure_failure setup_failure].include?(status)
    return "fake" if status.start_with?("fake_") || meta["adapter"] == "fake"
    run = meta["agent_run"]
    return "timeout" if status.match?(/timeout/i) || (run.is_a?(Hash) && run["timed_out"] == true)
    return "agent_failure" if status == "agent_failure"
    return "task_failure" if status == "task_failure" || (status == "complete" && correctness == false) || (status == "awaiting_review" && reviewed_task_failure?(node))
    return "awaiting_review" if status == "awaiting_review"
    return "complete" if correctness == true
    return "running" if status.empty? || status == "running"

    "infrastructure_failure"
  end

  def reviewed_task_failure?(node)
    return false unless node[:meta]["status"] == "awaiting_review"

    record = read_json(File.join(node[:path], "disposition.json"))
    return false unless record.is_a?(Hash)
    return false unless record["category"] == "task_failure"
    return false unless record["reason"].is_a?(String) && !record["reason"].strip.empty?
    return false unless record["no_pending_question"] == true

    record["meta_sha256"] == Digest::SHA256.file(File.join(node[:path], "meta.json")).hexdigest
  rescue Errno::ENOENT
    false
  end

  def cell_record(cell, index, nodes, disposition, correctness, final, identity_errors, retained, note = nil)
    first_run = nodes.first && nodes.first[:meta]["agent_run"]
    runs = nodes.map { |node| node[:meta]["agent_run"] }
    seconds = runs.map { |run| run.is_a?(Hash) ? run["seconds"] : nil }
    known_seconds = seconds.select { |value| value.is_a?(Numeric) }
    complete_seconds = !nodes.empty? && seconds.all? { |value| value.is_a?(Numeric) }
    {
      "grid_index" => index + 1,
      "cell" => cell,
      "disposition" => disposition,
      "correctness" => correctness,
      "recorded_status" => final ? final[:meta]["status"] : "unknown",
      "attempt_count" => nodes.length,
      "continuation_count" => note.to_s.include?("multiple continuations") ? "unknown" : [nodes.length - 1, 0].max,
      "first_agent_execution_seconds" => first_run.is_a?(Hash) && first_run["seconds"].is_a?(Numeric) ? first_run["seconds"] : "unknown",
      "all_agent_execution_seconds" => complete_seconds ? known_seconds.sum : "unknown",
      "known_agent_execution_seconds_sum" => known_seconds.empty? ? "unknown" : known_seconds.sum,
      "agent_execution_seconds_complete" => complete_seconds,
      "recorded_wall_seconds" => recorded_wall_seconds(nodes),
      "final_path" => final && relative_from_grid(final[:path]),
      "identity_errors" => identity_errors,
      "retention" => retained,
      "note" => note
    }
  end

  def recorded_wall_seconds(nodes)
    return "unknown" if nodes.empty?

    started = nodes.first[:meta]["started_at"]
    finished = nodes.last[:meta]["finished_at"]
    return "unknown" unless started.is_a?(String) && finished.is_a?(String)

    elapsed = Time.iso8601(finished) - Time.iso8601(started)
    elapsed >= 0 ? elapsed : "unknown"
  rescue ArgumentError, TypeError
    "unknown"
  end

  def relative_from_grid(path)
    grid_root = @grid_root
    grid_root ? Pathname.new(path).relative_path_from(Pathname.new(grid_root)).to_s : path
  end

  def absent_retention
    %w[meta snapshot checks baseline_bundle final_bundle patch transcript workspace container_reference].to_h { |key| [key, "unknown"] }
  end

  def recheck_info(cell_root, meta)
    history = File.join(cell_root, "verification-attempts")
    pointer = meta.is_a?(Hash) && meta["recheck_attempt"].is_a?(String) ? meta["recheck_attempt"] : nil
    unless File.directory?(history)
      return {
        "recheck_attempt_path" => pointer || "unknown",
        "recheck_audits" => "unknown",
        "checker_infrastructure_recovery_count" => "unknown"
      }
    end

    attempts = Dir.glob(File.join(history, "recheck-*")).select { |path| File.directory?(path) }
    audits = attempts.map { |path| read_json(File.join(path, "audit.json")) }
    passed = audits.count { |audit| audit.is_a?(Hash) && audit["passed"] == true }
    failed = audits.count { |audit| audit.is_a?(Hash) && audit["passed"] == false }
    unknown = attempts.length - passed - failed
    {
      "recheck_attempt_path" => pointer || "unknown",
      "recheck_audits" => {"attempts" => attempts.length, "passed" => passed, "failed" => failed, "unknown" => unknown},
      "checker_infrastructure_recovery_count" => unknown.zero? ? passed : "unknown"
    }
  end

  def retention(nodes, final)
    return absent_retention unless final

    root_path = nodes.first[:path]
    path = final[:path]
    files = {
      "meta" => File.file?(File.join(path, "meta.json")),
      "snapshot" => File.file?(File.join(path, "snapshot.json")),
      "checks" => File.file?(File.join(path, "checks.json")),
      "baseline_bundle" => File.file?(File.join(root_path, "baseline.bundle")),
      "final_bundle" => File.file?(File.join(path, "final.bundle")),
      "patch" => File.file?(File.join(path, "change.patch")),
      "transcript" => File.file?(File.join(path, "transcript.txt")),
      "workspace" => workspace_exists(final),
      "container_reference" => !final[:meta]["container"].to_s.empty?
    }
    files["core_artifacts_retained"] = %w[meta snapshot checks baseline_bundle final_bundle patch transcript].all? { |key| files[key] }
    files["all_attempt_metadata_retained"] = nodes.all? { |node| File.file?(File.join(node[:path], "meta.json")) }
    files["all_attempt_transcripts_retained"] = nodes.all? { |node| File.file?(File.join(node[:path], "transcript.txt")) }
    files["chain_attempts"] = nodes.length
    files
  end

  def workspace_exists(node)
    path = node[:meta]["workspace_path"]
    path = File.join(node[:path], "workspace") unless path.is_a?(String) && !path.empty?
    File.directory?(path)
  end

  def solution_metrics(first, final)
    return unknown_metrics unless first && final

    baseline_bundle = File.join(first[:path], "baseline.bundle")
    final_bundle = File.join(final[:path], "final.bundle")
    line_counts = net_line_counts(first, final)
    structural = StructureDiagnostics.from_bundles(baseline_bundle, final_bundle)
    {
      "production_changed_lines" => line_counts,
      "structural_delta" => structural["delta"] || "unknown",
      "dependency_files_changed" => structural["dependency_files_changed"] || "unknown"
    }
  rescue StandardError
    unknown_metrics
  end

  def net_line_counts(first, final)
    snapshot = {"baseline" => first[:snapshot].fetch("baseline"), "final" => final[:snapshot].fetch("final")}
    Dir.mktmpdir("grid-lines") do |dir|
      File.symlink(File.join(first[:path], "baseline.bundle"), File.join(dir, "baseline.bundle"))
      File.symlink(File.join(final[:path], "final.bundle"), File.join(dir, "final.bundle"))
      summary = PilotReport.diff_summary(dir, snapshot)
      counts = summary.fetch(:counts)
      production = counts.fetch(:production)
      return "unknown" unless production.values.all? { |value| value.is_a?(Numeric) }

      production.fetch(:added_lines) + production.fetch(:deleted_lines)
    end
  rescue StandardError
    "unknown"
  end

  def unknown_metrics
    {"production_changed_lines" => "unknown", "structural_delta" => "unknown", "dependency_files_changed" => "unknown"}
  end

  def passing_checks?(checks)
    checks.is_a?(Array) && !checks.empty? && checks.all? { |check| check.is_a?(Hash) && check["exit"] == 0 && check["timed_out"] != true }
  end

  def disposition_counts(records)
    DISPOSITIONS.to_h { |name| [name, records.count { |record| record["disposition"] == name }] }
  end

  def grouped_summaries(records)
    records.group_by { |record| record.fetch("cell").values_at("agent", "task", "track", "condition") }.sort_by { |key, _| key.map(&:to_s) }.map do |(agent, task, track, condition), group|
      correct = group.select { |record| record["correctness"] == true }
      dispositions = disposition_counts(group)
      {
        "agent" => agent,
        "task" => task,
        "track" => track,
        "condition" => condition,
        "assigned_cells" => group.length,
        "disposition_counts" => dispositions,
        "correct_solutions" => correct.length,
        "recorded_wall_seconds" => numeric_summary(correct.map { |record| record["recorded_wall_seconds"] }),
        "production_changed_lines" => numeric_summary(correct.map { |record| record.dig("solution_metrics", "production_changed_lines") }),
        "structural_deltas" => STRUCTURAL_FIELDS.to_h do |field|
          values = correct.map { |record| record.dig("solution_metrics", "structural_delta", field) }
          [field, numeric_summary(values)]
        end,
        "dependency_files_changed_count" => numeric_summary(correct.map { |record| dependency_count(record.dig("solution_metrics", "dependency_files_changed")) }),
        "retention" => {
          "core_artifacts_retained_cells" => group.count { |record| record.dig("retention", "core_artifacts_retained") == true },
          "container_reference_recorded_cells" => group.count { |record| record.dig("retention", "container_reference") == true }
        }
      }
    end
  end

  def numeric_summary(values)
    known = values.select { |value| value.is_a?(Numeric) }.sort
    unknown_count = values.length - known.length
    return {"n_known" => 0, "n_unknown" => unknown_count, "median" => "unknown", "range" => "unknown"} if known.empty?

    middle = known.length / 2
    median = known.length.odd? ? known[middle] : (known[middle - 1] + known[middle]) / 2.0
    {"n_known" => known.length, "n_unknown" => unknown_count, "median" => median, "range" => {"min" => known.first, "max" => known.last}}
  end

  def dependency_count(changes)
    return "unknown" unless changes.is_a?(Array)

    changes.length
  end

  def read_json(path)
    JSON.parse(File.read(path)) if File.file?(path)
  rescue JSON::ParserError
    nil
  end

  def relative(root, path)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: ruby scripts/grid_summary.rb RESULTS_ROOT" unless ARGV.length == 1

  begin
    puts JSON.pretty_generate(GridSummary.build(ARGV.fetch(0)))
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
