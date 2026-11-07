#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only descriptive join for contrast-v2's initial and fresh follow-up grids.
# Delegates cell/check/metric interpretation to the study's GridSummary.
require "json"
require "optparse"
require "pathname"
require "time"

module ContrastV2Report
  module_function

  IDENTITY = %w[task agent condition track repeat].freeze
  EXPECTED = 72

  def build(stage1_root:, stage2_root:, grid_summary_path:, output:, target: EXPECTED, frozen_inputs: nil)
    validate_output!(output, stage1_root, stage2_root, grid_summary_path, frozen_inputs)
    require File.expand_path(grid_summary_path)
    s1 = summarize(stage1_root)
    s2 = summarize(stage2_root)
    stage1, stage1_deviations, stage1_deviation_errors = apply_protocol_deviations(s1.fetch("cells"), stage1_root, "stage1")
    stage2, stage2_deviations, stage2_deviation_errors = apply_protocol_deviations(s2.fetch("cells"), stage2_root, "stage2")
    stage1_by_key = unique_index(stage1, "stage 1")
    unique_index(stage2, "stage 2")
    stage2_records = stage2.map do |record|
      key = identity_key(record.fetch("cell"))
      source = source_trial(record, stage2_root)
      original = stage1_by_key[key]
      errors = []
      errors << "no matching stage-1 assignment" unless original
      expected = original && expected_source(original, stage1_root)
      if expected && !source
        errors << "stage1_source_trial missing despite retained stage-1 final path"
      elsif expected && source && expected != source
        errors << "stage1_source_trial does not match joined stage-1 final path"
      end
      followup = errors.empty? ? followup_correctness(record, stage2_root) : "unknown"
      record.merge("stage1_source_trial" => source || "unknown", "join_errors" => errors,
                   "followup_correctness" => followup, "behavioral_eligible" => record.fetch("behavioral_eligible", true))
    end

    blocked_all = blocked_sidecars(stage2_root, stage2_records)
    blocked = blocked_all.select { |entry| entry["current"] }
    historical_blocked = blocked_all.reject { |entry| entry["current"] }
    blocked_by_index = blocked.group_by { |entry| entry["grid_index"] }
    sidecar_errors = []
    stage2_records.each do |record|
      sidecars = blocked_by_index[record["grid_index"]] || []
      if sidecars.length > 1
        sidecar_errors << {"grid_index" => record["grid_index"], "error" => "multiple blocked sidecars"}
        next
      end
      sidecar = sidecars.first
      next unless sidecar
      if sidecar["cell"] && identity_key(sidecar["cell"]) != identity_key(record.fetch("cell"))
        sidecar_errors << {"grid_index" => record["grid_index"], "error" => "blocked sidecar assignment identity mismatch"}
        next
      end
      record["blocked_sidecar"] = sidecar
      record["raw_disposition"] ||= record["disposition"]
      record["disposition"] = "blocked"
      record["correctness"] = "unknown"
      record["followup_correctness"] = "unknown"
    end
    blocked.each do |entry|
      index = entry["grid_index"]
      sidecar_errors << {"grid_index" => index, "error" => "blocked sidecar has no matching assignment"} unless index.is_a?(Integer) && stage2_records.any? { |r| r["grid_index"] == index }
    end
    invalid_source_assignments = []
    stage2_records.each do |record|
      original = stage1_by_key[identity_key(record.fetch("cell"))]
      deviation = original && original["protocol_deviation"]
      next unless deviation
      record["raw_disposition"] ||= record["disposition"]
      record["disposition"] = "blocked"
      record["correctness"] = "unknown"
      record["followup_correctness"] = "unknown"
      record["behavioral_eligible"] = false
      record["invalid_source_blocked"] = true
      record["source_protocol_deviation"] = deviation
      invalid_source_assignments << {"grid_index" => record["grid_index"], "cell" => record["cell"],
                                     "stage2_disposition" => "blocked", "reason" => "stage-1 source is an operator protocol deviation",
                                     "protocol_deviation_sidecar" => deviation["sidecar_path"]}
    end
    original_baseline_records = original_baseline_metrics(stage1, stage2_records, stage1_root, stage2_root)

    s1_stats = correctness_stats(stage1.map { |r| r["correctness"] })
    s2_stats = correctness_stats(stage2_records.map { |r| r["correctness"] })
    followup_stats = correctness_stats(stage2_records.map { |r| r["followup_correctness"] })
    conditional = conditional_followup(stage1, stage2_records)
    conditional_cumulative = conditional_stage2(stage1, stage2_records)
    actual_models = model_observations(stage1_root, stage2_root)
    code_index = code_index_rows(stage1, stage2_records, stage1_root, stage2_root)
    document = {
      "generated_at" => Time.now.utc.iso8601,
      "state" => "in_progress",
      "target_assigned_cells_per_stage" => target,
      "planned_cells" => {"stage1" => target, "stage2" => target},
      "assigned_cells" => {"stage1" => stage1.length, "stage2" => stage2.length},
      "stage1_cells" => stage1,
      "stage2_cells" => stage2_records,
      "stage1_correctness" => s1_stats,
      "stage1_behavioral_correctness" => correctness_stats(stage1.select { |r| r["behavioral_eligible"] }.map { |r| r["correctness"] }),
      "stage2_cumulative_correctness" => s2_stats,
      "stage2_behavioral_correctness" => correctness_stats(stage2_records.select { |r| r["behavioral_eligible"] }.map { |r| r["correctness"] }),
      "stage2_followup_check_correctness" => followup_stats,
      "followup_correctness_conditional_on_stage1_correct" => conditional,
      "stage2_cumulative_correctness_conditional_on_stage1_correct" => conditional_cumulative,
      "stage2_blocked_sidecars" => {"count" => blocked.length, "entries" => blocked},
      "stage2_historical_blocked_sidecars" => {"count" => historical_blocked.length, "entries" => historical_blocked},
      "protocol_deviations" => {"count" => stage1_deviations.length + stage2_deviations.length,
                                "stage1_count" => stage1_deviations.length, "stage2_count" => stage2_deviations.length,
                                "entries" => stage1_deviations + stage2_deviations,
                                "errors" => stage1_deviation_errors + stage2_deviation_errors},
      "stage2_invalid_source_assignments" => {"count" => invalid_source_assignments.length, "entries" => invalid_source_assignments},
      "sidecar_accounting" => sidecar_accounting(stage2_records, blocked, sidecar_errors),
      "actual_model_observations" => actual_models,
      "model_note" => "Requested Codex model is gpt-6.1-sol; actual Codex model remains unknown unless a trial records actual_model (or agent_run.actual_model). Claude actual model is reported only when recorded. Requested model names are not treated as actual-model evidence.",
      "time" => {"stage1" => time_summary(stage1), "stage2_incremental" => time_summary(stage2_records),
                 "stage2_cumulative_agent_seconds" => cumulative_agent_time(stage1, stage2_records),
                 "wall_time_note" => "Recorded wall seconds are elapsed recorded trial spans, not agent execution. Stage 2 has a fresh session; its incremental code metric uses the prepared stage-1 final baseline, while a separately labeled final-state metric compares stage-2 final code to the original stage-1 baseline."},
      "production_metrics" => {"stage1_initial_patch" => GridSummary.grouped_summaries(stage1),
                                "stage2_incremental_patch_from_stage1_final" => GridSummary.grouped_summaries(stage2_records),
                                "stage2_final_vs_original_stage1_baseline" => GridSummary.grouped_summaries(original_baseline_records)},
      "code_index" => code_index,
      "review_blinding_note" => "Report joins use assignment identity and stage1_source_trial only. Blinded review packet keys remain private and are not read or interpreted.",
      "winner_note" => "Descriptive evidence only. No weighted winner, quality grade, or statistical winner is computed."
    }
    document["state"] = final_gate(document, target) ? "complete_#{target}_each_sidecars_accounted" : "in_progress"
    write_outputs(output, document)
    document
  end

  def summarize(root)
    return {"assigned_cells" => 0, "cells" => [], "groups" => []} unless File.file?(File.join(root, "grid.json"))
    GridSummary.build(root)
  end

  def identity_key(cell)
    IDENTITY.map { |field| cell[field] }
  end

  def apply_protocol_deviations(records, root, stage)
    deviations = []
    errors = []
    annotated = records.map do |record|
      record["behavioral_eligible"] = true
      path = File.join(root, format("%04d", record.fetch("grid_index")), "protocol-deviation.json")
      next record unless File.file?(path)
      sidecar = read_json(path)
      unless sidecar.is_a?(Hash)
        errors << {"stage" => stage, "grid_index" => record["grid_index"], "sidecar_path" => path, "error" => "protocol-deviation sidecar is invalid JSON/object"}
        next record
      end
      next record unless sidecar["eligible_behavioral_trial"] == false

      link = File.realpath(path)
      deviation = {"stage" => stage, "grid_index" => record["grid_index"], "cell" => record["cell"],
                   "classification" => sidecar["classification"] || "protocol_deviation",
                   "sidecar_path" => link, "eligible_behavioral_trial" => false,
                   "raw_disposition" => record["disposition"]}
      deviations << deviation
      record.merge("raw_disposition" => record["disposition"], "raw_correctness" => record["correctness"],
                   "disposition" => "operator_error", "correctness" => "unknown",
                   "behavioral_eligible" => false, "protocol_deviation" => deviation)
    rescue JSON::ParserError => error
      errors << {"stage" => stage, "grid_index" => record["grid_index"], "sidecar_path" => path, "error" => error.message}
      record
    end
    [annotated, deviations, errors]
  end

  def unique_index(records, label)
    records.each_with_object({}) do |record, index|
      key = identity_key(record.fetch("cell"))
      raise "duplicate #{label} cell identity: #{key.inspect}" if index.key?(key)
      index[key] = record
    end
  end

  def source_trial(record, root)
    index = record.fetch("grid_index")
    path = File.join(root, format("%04d", index), "meta.json")
    meta = read_json(path) if File.file?(path)
    source = meta["stage1_source_trial"] if meta.is_a?(Hash)
    if !source && (sidecar_path = File.join(root, "stage2-blocked", format("%04d.json", index))) && File.file?(sidecar_path)
      sidecar = read_json(sidecar_path)
      source = sidecar["stage1_source_trial"] if sidecar.is_a?(Hash)
    end
    return nil unless source.is_a?(String)
    File.realpath(source)
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  def expected_source(record, root)
    rel = record["final_path"]
    return nil unless rel.is_a?(String) && rel != "unknown"
    File.realpath(File.join(root, rel))
  rescue Errno::ENOENT
    nil
  end

  def followup_correctness(record, root)
    relative = record["final_path"]
    return "unknown" unless relative.is_a?(String) && relative != "unknown"
    path = File.expand_path(File.join(relative, "checks.json"), root)
    return "unknown" unless path_within?(path, File.expand_path(root))
    checks = read_json(path)
    return "unknown" unless checks.is_a?(Array)
    targeted = checks.select do |check|
      command = check.is_a?(Hash) ? [check["command"], check["argv"], check["label"]].flatten.compact.join(" ") : ""
      command.match?(/_followup(?:\.rb)?\b/i)
    end
    return "unknown" if targeted.empty?
    return false if targeted.any? { |check| check["exit"] != 0 || check["timed_out"] == true }
    true
  rescue Errno::ENOENT, JSON::ParserError
    "unknown"
  end

  def correctness_stats(values)
    {"correct" => values.count(true), "incorrect" => values.count(false), "unknown" => values.count("unknown"),
     "assigned_denominator" => values.length, "known_denominator" => values.count(true) + values.count(false)}
  end

  def conditional_followup(stage1, stage2)
    by_key = stage2.to_h { |r| [identity_key(r.fetch("cell")), r] }
    eligible = stage1.select { |r| r["correctness"] == true }
    results = eligible.map do |r|
      value = by_key.dig(identity_key(r.fetch("cell")), "followup_correctness")
      value.nil? ? "unknown" : value
    end
    correctness_stats(results).merge("condition" => "stage-1 checker-correct assignments only")
  end

  def conditional_stage2(stage1, stage2)
    by_key = stage2.to_h { |r| [identity_key(r.fetch("cell")), r] }
    eligible = stage1.select { |r| r["correctness"] == true }
    results = eligible.map do |r|
      value = by_key.dig(identity_key(r.fetch("cell")), "correctness")
      value.nil? ? "unknown" : value
    end
    correctness_stats(results).merge("condition" => "stage-1 checker-correct assignments only")
  end

  def original_baseline_metrics(stage1, stage2, stage1_root, stage2_root)
    stage1_by_key = stage1.to_h { |record| [identity_key(record.fetch("cell")), record] }
    stage2.map do |record|
      original = stage1_by_key[identity_key(record.fetch("cell"))]
      eligible = original && record["correctness"] == true && record.fetch("join_errors", []).empty? &&
        !original["protocol_deviation"] && !record["source_protocol_deviation"] && !record["invalid_source_blocked"]
      metrics = if eligible
        stage1_path = File.join(stage1_root, format("%04d", original.fetch("grid_index")))
        stage1_snapshot = read_json(File.join(stage1_path, "snapshot.json"))
        final_path = absolute_trial_path(stage2_root, record["final_path"])
        final_path = File.realpath(final_path) if final_path != "unknown"
        final_snapshot = final_path != "unknown" ? read_json(File.join(final_path, "snapshot.json")) : nil
        if stage1_snapshot.is_a?(Hash) && final_snapshot.is_a?(Hash) && final_path != "unknown" && path_within?(final_path, File.realpath(stage2_root))
          GridSummary.solution_metrics({path: stage1_path, snapshot: stage1_snapshot},
                                       {path: final_path, snapshot: final_snapshot})
        else
          {"production_changed_lines" => "unknown", "structural_delta" => "unknown", "dependency_files_changed" => "unknown"}
        end
      else
        {"production_changed_lines" => "unknown", "structural_delta" => "unknown", "dependency_files_changed" => "unknown"}
      end
      record.merge("correctness" => eligible ? true : "unknown", "solution_metrics" => metrics,
                   "metric_label" => "stage-2 final relative to original stage-1 baseline")
    rescue Errno::ENOENT, JSON::ParserError
      record.merge("correctness" => "unknown",
                   "solution_metrics" => {"production_changed_lines" => "unknown", "structural_delta" => "unknown", "dependency_files_changed" => "unknown"},
                   "metric_label" => "stage-2 final relative to original stage-1 baseline")
    end
  end

  def blocked_sidecars(root, stage2_records)
    records_by_index = stage2_records.to_h { |record| [record["grid_index"], record] }
    Dir.glob(File.join(root, "stage2-blocked", "*.json")).sort.filter_map do |path|
      entry = read_json(path)
      next unless entry.is_a?(Hash) && entry["status"] == "blocked"
      index = entry["grid_index"]
      trial_meta = File.join(root, format("%04d", index), "meta.json") if index.is_a?(Integer)
      entry.merge("current" => !(trial_meta && File.file?(trial_meta)),
                  "current_disposition" => records_by_index.dig(index, "disposition"))
    rescue JSON::ParserError
      {"status" => "unreadable_blocked_sidecar", "path" => path}
    end
  end

  def sidecar_accounting(stage2, blocked, errors)
    counts = Hash.new(0)
    stage2.each { |r| counts[r.fetch("disposition", "unknown")] += 1 }
    sidecar_blocked = stage2.count { |r| r["disposition"] == "blocked" && r["blocked_sidecar"] }
    invalid_source_only = stage2.count { |r| r["disposition"] == "blocked" && r["invalid_source_blocked"] && !r["blocked_sidecar"] }
    {"stage2_grid_dispositions" => counts, "blocked_sidecars" => blocked.length,
     "sidecar_accounted_blocked_assignments" => sidecar_blocked,
     "invalid_source_blocked_assignments" => invalid_source_only,
     "accounted_blocked_assignments" => sidecar_blocked + invalid_source_only,
     "accounted_assignments" => stage2.length, "errors" => errors,
     "note" => "Blocked sidecars are retained as explicit blocked assignments and not silently counted as unstarted or omitted."}
  end

  def time_summary(records)
    first = records.filter_map { |r| numeric(r["first_agent_execution_seconds"]) }
    cumulative = records.filter_map { |r| numeric(r["all_agent_execution_seconds"]) }
    wall = records.filter_map { |r| numeric(r["recorded_wall_seconds"]) }
    {"first_turn_agent_seconds_sum_known" => first.sum, "first_turn_known_cells" => first.length,
     "followups_cumulative_agent_seconds_sum_known" => cumulative.sum, "cumulative_known_cells" => cumulative.length,
     "recorded_wall_seconds_sum_known" => wall.sum, "wall_known_cells" => wall.length,
     "unknown_cells" => records.length - cumulative.length}
  end

  def cumulative_agent_time(stage1, stage2)
    s1 = stage1.filter_map { |r| numeric(r["all_agent_execution_seconds"]) }
    s2 = stage2.filter_map { |r| numeric(r["all_agent_execution_seconds"]) }
    s2_by_key = stage2.to_h { |r| [identity_key(r.fetch("cell")), numeric(r["all_agent_execution_seconds"])] }
    paired = stage1.count do |r|
      numeric(r["all_agent_execution_seconds"]) && s2_by_key[identity_key(r.fetch("cell"))]
    end
    {"stage1_sum_known" => s1.sum, "stage1_known_cells" => s1.length,
     "stage2_incremental_sum_known" => s2.sum, "stage2_incremental_known_cells" => s2.length,
     "joined_sum_known" => s1.sum + s2.sum, "joined_stage_pairs_complete" => paired,
     "joined_stage_pairs_missing_component" => stage1.length - paired,
     "interpretation" => "Per-cell initial plus fresh follow-up execution duration where both are recorded; unknown components are not imputed."}
  end

  def model_observations(*roots)
    found = Hash.new { |hash, key| hash[key] = [] }
    roots.each do |root|
      Dir.glob(File.join(root, "[0-9]*/meta.json")).sort.each do |path|
        meta = read_json(path)
        next unless meta.is_a?(Hash)
        agent = meta["agent"] || "unknown"
        cell_index = File.basename(File.dirname(path)).to_i
        cell_root = File.join(root, format("%04d", cell_index))
        nodes, = GridSummary.read_chain(cell_root)
        nodes.each do |node|
          node_meta = node[:meta]
          actual = node_meta["actual_model"] || node_meta.dig("agent_run", "actual_model")
          found[agent] << actual if actual.is_a?(String) && !actual.empty?
        end
      rescue JSON::ParserError
        next
      end
    end
    {"codex" => (found["codex"].uniq.empty? ? "unknown" : found["codex"].uniq),
     "claude" => (found["claude"].uniq.empty? ? "unknown" : found["claude"].uniq)}
  end

  def code_index_rows(stage1, stage2, stage1_root, stage2_root)
    stage2_by_key = stage2.to_h { |r| [identity_key(r.fetch("cell")), r] }
    stage1.map do |r|
      s2 = stage2_by_key[identity_key(r.fetch("cell"))]
      {"cell" => r.fetch("cell"), "stage1_disposition" => r["disposition"], "stage2_disposition" => s2 && s2["disposition"],
       "stage1_final_path" => absolute_trial_path(stage1_root, r["final_path"]),
       "stage2_final_path" => s2 && absolute_trial_path(stage2_root, s2["final_path"]),
       "stage1_source_trial" => s2 ? s2["stage1_source_trial"] : "unknown",
       "join_errors" => s2 ? s2["join_errors"] : ["no matching stage-2 assignment"]}
    end
  end

  def absolute_trial_path(root, relative)
    return "unknown" unless relative.is_a?(String) && relative != "unknown"
    File.expand_path(relative, root)
  end

  def final_gate(document, target)
    assigned = document.fetch("assigned_cells")
    return false unless assigned.values.all? { |value| value == target }
    accounting = document.fetch("sidecar_accounting")
    accounting.fetch("accounted_assignments") == target &&
      document.fetch("stage2_blocked_sidecars").fetch("count") == accounting.fetch("sidecar_accounted_blocked_assignments") &&
      accounting.fetch("accounted_blocked_assignments") == accounting.fetch("stage2_grid_dispositions").fetch("blocked", 0) &&
      accounting.fetch("errors").empty? &&
      document.fetch("protocol_deviations").fetch("errors").empty? &&
      (document.fetch("stage1_cells") + document.fetch("stage2_cells")).all? { |r| r["disposition"] != "operator_error" || r["protocol_deviation"].is_a?(Hash) } &&
      document.fetch("code_index").all? { |r| r.fetch("join_errors").empty? } &&
      document.fetch("stage2_cells").all? { |r| r.fetch("join_errors").empty? } &&
      (document.fetch("stage1_cells") + document.fetch("stage2_cells")).none? do |record|
        %w[running unstarted awaiting_review identity_mismatch fake].include?(record["disposition"]) ||
          (record["identity_errors"].is_a?(Array) && !record["identity_errors"].empty?)
      end
  end

  def validate_output!(output, stage1_root, stage2_root, grid_summary_path, frozen_inputs)
    candidate = resolved_path(output)
    grid_summary_file = File.file?(grid_summary_path) ? File.realpath(grid_summary_path) : File.expand_path(grid_summary_path)
    source_root = File.dirname(File.dirname(grid_summary_file))
    frozen_roots = [frozen_inputs].compact
    [stage1_root, stage2_root].each do |root|
      frozen_roots.concat(Dir.glob(File.join(File.dirname(File.expand_path(root)), "*-protocol", "inputs")))
    end
    protected = [stage1_root, stage2_root, source_root, *frozen_roots].map { |root| resolved_path(root) }
    offender = protected.find { |root| path_within?(candidate, root) }
    raise "output directory is inside a protected grid, frozen input, or source root: #{offender}" if offender
    if File.directory?(candidate) && %w[summary.json report.md].any? { |name| File.exist?(File.join(candidate, name)) }
      raise "refusing to overwrite existing report output files in #{candidate}"
    end
    raise "output path exists and is not a directory: #{candidate}" if File.exist?(candidate) && !File.directory?(candidate)
  end

  def resolved_path(path)
    absolute = File.expand_path(path)
    suffix = []
    cursor = absolute
    until File.exist?(cursor)
      suffix.unshift(File.basename(cursor))
      parent = File.dirname(cursor)
      raise "cannot resolve path: #{path}" if parent == cursor
      cursor = parent
    end
    File.join(File.realpath(cursor), *suffix)
  end

  def path_within?(path, root)
    expanded_path = File.expand_path(path)
    expanded_root = File.expand_path(root)
    expanded_path == expanded_root || expanded_path.start_with?(expanded_root + File::SEPARATOR)
  end

  def numeric(value)
    value if value.is_a?(Numeric)
  end

  def read_json(path)
    JSON.parse(File.read(path))
  end

  def write_outputs(output, document)
    require "fileutils"
    FileUtils.mkdir_p(output)
    File.write(File.join(output, "summary.json"), JSON.pretty_generate(document) + "\n")
    lines = ["# Contrast v2 stage and follow-up report", "", "State: **#{document.fetch('state')}**.", "",
      "Planned assignments: #{document.dig('planned_cells', 'stage1')} per stage. Current grids contain #{document.dig('assigned_cells', 'stage1')} stage-1 and #{document.dig('assigned_cells', 'stage2')} stage-2 assignments; a missing grid is reported as 0 currently assigned, not as a completed empty stage.", "",
      "| Stage | Correct | Incorrect | Unknown | Assigned denominator |", "|---|---:|---:|---:|---:|"]
    {"Stage 1 initial (all assigned)" => document["stage1_correctness"],
     "Stage 2 cumulative checks (all assigned)" => document["stage2_cumulative_correctness"],
     "Stage 2 follow-up-specific checks (all assigned)" => document["stage2_followup_check_correctness"],
     "Stage 2 cumulative checks (conditional on stage-1 correct)" => document["stage2_cumulative_correctness_conditional_on_stage1_correct"],
     "Follow-up-specific checks (conditional on stage-1 correct)" => document["followup_correctness_conditional_on_stage1_correct"]}.each do |name, stats|
      lines << "| #{name} | #{stats['correct']} | #{stats['incorrect']} | #{stats['unknown']} | #{stats['assigned_denominator']} |"
    end
    {"Stage 1 valid behavioral trials" => document["stage1_behavioral_correctness"],
     "Stage 2 valid behavioral trials" => document["stage2_behavioral_correctness"]}.each do |name, stats|
      lines << "| #{name} | #{stats['correct']} | #{stats['incorrect']} | #{stats['unknown']} | #{stats['assigned_denominator']} |"
    end
    lines.concat(["", "Stage-2 incremental production and structural measurements use the prepared stage-1 final workspace as baseline. A separate stage-2 final-versus-original-stage-1-baseline metric compares final states directly; it is not the sum of the initial and follow-up change counts. These final-baseline metrics include only matched, provenance-valid, stage-2 checker-correct pairs without a source protocol deviation. Stage-2 checks include the original checks plus follow-up checks; the follow-up-only row counts checks whose recorded command identifies a `_followup.rb` check. Missing bundles or snapshots remain unknown.",
      "", "The conditional follow-up denominator contains only stage-1 checker-correct assignments. Unconditional rows retain the full assigned denominator.",
      "", "Operator protocol deviations are controller errors, not plugin/model failures. They remain in assigned denominators as correctness unknown and are excluded from valid behavioral denominators.",
      "", "## Operator protocol deviations", "", "| Stage | # | Task | Classification | Raw disposition | Sidecar |", "|---|---:|---|---|---|---|"])
    document.dig("protocol_deviations", "entries").each do |entry|
      cell = entry["cell"] || {}
      row = [entry["stage"], entry["grid_index"], cell["task"], entry["classification"], entry["raw_disposition"], path_link(entry["sidecar_path"], "protocol-deviation.json")]
      lines << "| #{row.map { |value| escape(value || 'unknown') }.join(' | ')} |"
    end
    lines.concat(["", "Stage-2 assignments blocked because their initial source is invalid: #{document.dig('stage2_invalid_source_assignments', 'count')}."])
    document.dig("stage2_invalid_source_assignments", "entries").each do |entry|
      cell = entry["cell"] || {}
      lines << "- Assignment #{escape(entry['grid_index'])}: #{escape(cell['task'])} (#{escape(entry['reason'])}); [source protocol-deviation sidecar](#{entry['protocol_deviation_sidecar']})."
    end
    lines.concat([
      "", "Blocked sidecars: #{document.dig('stage2_blocked_sidecars', 'count')}; assignment accounting: #{document.dig('sidecar_accounting', 'accounted_assignments')}/#{document['target_assigned_cells_per_stage']}.",
      "", "## Blocked stage-2 assignments", "", "| # | Task | Agent | Track | Condition | Repeat | Reason |", "|---:|---|---|---|---|---:|---|"])
    document.dig("stage2_blocked_sidecars", "entries").each do |entry|
      cell = entry["cell"] || {}
      row = [entry["grid_index"], cell["task"], cell["agent"], cell["track"], cell["condition"], cell["repeat"], entry["reason"] || entry["status"]]
      lines << "| #{row.map { |value| escape(value || 'unknown') }.join(' | ')} |"
    end
    lines.concat(["", "Historical blocked sidecars superseded by recorded stage-2 trials: #{document.dig('stage2_historical_blocked_sidecars', 'count')}."])
    document.dig("stage2_historical_blocked_sidecars", "entries").each do |entry|
      cell = entry["cell"] || {}
      lines << "- Assignment #{escape(entry['grid_index'] || 'unknown')}: #{escape(cell['task'] || 'unknown')} / #{escape(entry['reason'] || entry['status'] || 'unknown')} (historical; not counted as currently blocked)."
    end
    lines.concat([
      "", "## Production-change metrics", "", "The stage-2 final-versus-original metric is computed from original stage-1 baseline to final stage-2 state, not by adding line counts across patches.",
      "", "| Measurement | Agent | Task | Track | Condition | Correct cells | Median production changed lines |", "|---|---|---|---|---|---:|---:|"])
    {"Stage 1 initial patch" => document.dig("production_metrics", "stage1_initial_patch"),
     "Stage 2 incremental patch" => document.dig("production_metrics", "stage2_incremental_patch_from_stage1_final"),
     "Stage 2 final vs original stage-1 baseline" => document.dig("production_metrics", "stage2_final_vs_original_stage1_baseline")}.each do |stage_name, groups|
      Array(groups).each do |group|
        metric = group.dig("production_changed_lines", "median")
        row = [stage_name, group["agent"], group["task"], group["track"], group["condition"], group["correct_solutions"], metric || "unknown"]
        lines << "| #{row.map { |value| escape(value || 'unknown') }.join(' | ')} |"
      end
    end
    lines.concat([
      "", "Agent seconds are execution durations; wall seconds are recorded elapsed spans. The joined total adds initial and incremental follow-up durations only where recorded.",
      "", document.fetch("winner_note"), document.fetch("review_blinding_note"), "",
      "## Code index", "", "Each row retains stage paths for audit. The private blinded-review key is not consumed or exposed.", "",
      "| Task | Agent | Track | Condition | Repeat | Stage 1 | Stage 2 | Stage-1 source link |", "|---|---|---|---|---:|---|---|---|"])
    document.fetch("code_index").each do |row|
      cell = row.fetch("cell")
      values = [cell["task"], cell["agent"], cell["track"], cell["condition"], cell["repeat"],
                path_link(row["stage1_final_path"], "stage 1"), path_link(row["stage2_final_path"], "stage 2"),
                path_link(row["stage1_source_trial"], "stage-1 source")]
      lines << "| #{values.map { |value| escape(value || 'unknown') }.join(' | ')} |"
    end
    File.write(File.join(output, "report.md"), lines.join("\n") + "\n")
  end

  def escape(value)
    value.to_s.gsub("|", "\\|").gsub("\n", " ")
  end

  def path_link(path, label)
    return "unknown" unless path.is_a?(String) && path != "unknown"
    "[#{label}](#{path.gsub(' ', '%20')})"
  end

  def cli
    options = {}
    OptionParser.new do |p|
      p.banner = "ruby contrast_v2_report.rb --stage1 DIR --stage2 DIR --grid-summary PATH --output DIR [--target 72]"
      p.on("--stage1 DIR") { |v| options[:stage1_root] = v }
      p.on("--stage2 DIR") { |v| options[:stage2_root] = v }
      p.on("--grid-summary PATH") { |v| options[:grid_summary_path] = v }
      p.on("--output DIR") { |v| options[:output] = v }
      p.on("--target N", Integer) { |v| options[:target] = v }
    end.parse!
    %i[stage1_root stage2_root grid_summary_path output].each { |key| raise "--#{key.to_s.tr('_', '-')} required" unless options[key] }
    build(**options)
  end
end

ContrastV2Report.cli if $PROGRAM_NAME == __FILE__
