#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "rbconfig"
require "shellwords"
require_relative "prepare_stage2"
require_relative "support/grid_summary"

module ContrastV2Grid
  module_function

  def prepare(stage1_root:, catalog:, output:, prepared_root:, stage_kind:, image: nil, runner: nil, resume_script: nil, resume: false)
    source_grid_root = File.realpath(stage1_root)
    catalog_root = File.realpath(catalog)
    output_root = File.expand_path(output)
    catalogs_root = File.expand_path(prepared_root)
    raise "prepared catalog root must be outside stage-2 grid root" if within?(catalogs_root, output_root)
    raise "stage-2 grid root cannot contain prepared catalogs" if within?(output_root, catalogs_root)

    source_grid = JSON.parse(File.read(File.join(source_grid_root, "grid.json")))
    summary = GridSummary.build(source_grid_root)
    source_records = summary.fetch("cells")
    cells = source_grid.fetch("cells")
    raise "GridSummary cell count differs from grid manifest" unless source_records.length == cells.length
    options = source_grid.fetch("options", {}).dup
    options["output"] = output_root
    options["image"] = image || "llmx-contrast-v2-minimal:20261102"
    options["stage_kind"] = stage_kind
    options["stage2_prepared_root"] = catalogs_root
    assigned = {"options" => options, "cells" => cells}

    if File.exist?(output_root)
      raise "stage-2 output already exists; pass --resume to continue" unless resume
      existing = JSON.parse(File.read(File.join(output_root, "grid.json")))
      raise "existing stage-2 assignments differ" unless existing["cells"] == cells
      raise "existing stage-2 output path differs" unless File.expand_path(existing.dig("options", "output")) == output_root
      raise "existing stage-2 kind differs" unless existing.dig("options", "stage_kind") == stage_kind
      raise "existing prepared root differs" unless File.expand_path(existing.dig("options", "stage2_prepared_root")) == catalogs_root
      raise "existing stage-2 image differs" unless existing.dig("options", "image") == options["image"]
    else
      raise "--resume requested but stage-2 output does not exist" if resume
      FileUtils.mkdir_p(output_root)
      write_json(File.join(output_root, "grid.json"), assigned)
    end
    FileUtils.mkdir_p(catalogs_root)
    stage2_records = GridSummary.build(output_root).fetch("cells")

    runner_path = File.expand_path(runner || File.join(__dir__, "run_stage2.rb"))
    resume_path = File.expand_path(resume_script || File.join(__dir__, "support", "resume.rb"))
    entries = cells.each_with_index.map do |cell, index|
      source_record = source_records.fetch(index)
      stage2_record = stage2_records.fetch(index)
      cell_output = File.join(output_root, format("%04d", index + 1))
      prepared = File.join(catalogs_root, format("%04d", index + 1))
      plan_path = File.join(prepared, "stage2-plan.json")
      source_trial = resolve_source(source_grid_root, source_record)
      protocol_deviation = protocol_deviation_for(source_grid_root, index)
      if protocol_deviation && protocol_deviation["eligible_behavioral_trial"] == false
        entry = blocked_entry(cell, index, "invalidoperator-source: stage-1 root cell is flagged ineligible", source_record, source_trial)
        entry["protocol_deviation"] = protocol_deviation
        write_grid_sidecar(output_root, "blocked", index, entry)
        next(entry)
      end
      if File.file?(File.join(cell_output, "meta.json"))
        existing_entry = existing_stage2_entry(cell_output, cell, index, output_root, resume_path, stage2_record)
        write_json(plan_path, existing_entry) unless File.file?(plan_path)
        next(existing_entry)
      end

      unless source_trial
        entry = blocked_entry(cell, index, "GridSummary has no retained final path", source_record)
        write_grid_sidecar(output_root, "blocked", index, entry)
        next(entry)
      end
      source_meta = read_json(File.join(source_trial, "meta.json"))
      unless source_meta.is_a?(Hash) && source_meta["workspace_stable"] == true && source_meta["restoration_verified"] == true
        entry = blocked_entry(cell, index, "stage-1 final workspace/snapshot is not stable and verified", source_record, source_trial)
        write_grid_sidecar(output_root, "blocked", index, entry)
        next(entry)
      end
      if source_record["identity_errors"].any?
        entry = blocked_entry(cell, index, "GridSummary found stage-1 identity errors", source_record, source_trial)
        write_grid_sidecar(output_root, "blocked", index, entry)
        next(entry)
      end

      # A genuine pending question must be answered through the existing resume
      # helper. This planner only emits the command and a response-file path.
      if source_record["disposition"] == "awaiting_review"
        entry = clarification_entry(cell, index, source_trial, source_meta, resume_path, output_root)
        write_grid_sidecar(output_root, "clarifications", index, entry)
        next(entry)
      end
      if %w[running unstarted fake identity_mismatch].include?(source_record["disposition"])
        entry = blocked_entry(cell, index, "stage-1 source is not a stable terminal behavioral result (#{source_record['disposition']})", source_record, source_trial)
        write_grid_sidecar(output_root, "blocked", index, entry)
        next(entry)
      end

      begin
        manifest = if File.file?(File.join(prepared, "stage2-manifest.json"))
          validate_prepared(prepared, source_trial, cell, stage_kind)
        else
          ContrastV2.prepare(source_trial: source_trial, catalog: catalog_root, output: prepared, stage_kind: stage_kind)
        end
        manifest["repeat"] = cell["repeat"]
        write_json(File.join(prepared, "stage2-manifest.json"), manifest)
        command = stage2_command(runner_path, prepared, cell, index, source_grid.fetch("options", {}), output_root, image)
        entry = {
          "grid_index" => index + 1, "cell" => cell, "status" => "prepared",
          "stage1_final_path" => source_trial, "prepared_catalog" => prepared,
          "command_argv" => command, "command" => Shellwords.join(command),
          "stage1_disposition" => source_record["disposition"], "stage1_correctness" => source_record["correctness"]
        }
        write_json(plan_path, entry)
        entry
      rescue StandardError => error
        entry = blocked_entry(cell, index, "stage-2 preparation failed: #{error.class}: #{error.message}", source_record, source_trial)
        write_grid_sidecar(output_root, "blocked", index, entry)
        entry
      end
    end

    ready = entries.find { |entry| entry["status"] == "prepared" }
    clarification = entries.find { |entry| entry["status"] == "clarification_required" }
    next_entry = ready || clarification
    plan = {
      "stage" => 2,
      "stage_kind" => stage_kind,
      "stage1_grid" => source_grid_root,
      "stage2_grid" => output_root,
      "prepared_catalog_root" => catalogs_root,
      "assigned_cells" => cells.length,
      "status_counts" => entries.map { |entry| entry["status"] }.tally,
      "next" => next_entry,
      "cells" => entries
    }
    write_json(File.join(output_root, "stage2-plan.json"), plan)
    plan
  end

  def stage2_command(runner, prepared, cell, index, options, output_root, image_override)
    agent = cell.fetch("agent")
    model = options.fetch("#{agent}_model")
    image = image_override || "llmx-contrast-v2-minimal:20261102"
    auth = options.fetch("#{agent}_auth_file")
    output = File.join(output_root, format("%04d", index + 1))
    [RbConfig.ruby, runner, "--prepared", prepared, "--task", cell.fetch("task"),
     "--agent", agent, "--model", model, "--condition", cell.fetch("condition"),
     "--track", cell.fetch("track"), "--output", output, "--image", image, "--auth-file", auth]
  end

  def existing_stage2_entry(cell_output, cell, index, output_root, resume_script, summary)
    final_relative = summary["final_path"]
    final_path = final_relative && File.expand_path(final_relative, output_root)
    if summary["disposition"] == "awaiting_review" && final_path
      meta = read_json(File.join(final_path, "meta.json")) || {}
      clarification_entry(cell, index, final_path, meta, resume_script, output_root).merge("stage2_disposition" => summary["disposition"])
    else
      state = case summary["disposition"]
      when "complete", "task_failure" then "already_terminal"
      when "running" then "in_progress"
      else "needs_review"
      end
      {"grid_index" => index + 1, "cell" => cell, "status" => state,
       "stage2_disposition" => summary["disposition"], "final_path" => final_path}
    end
  end

  def clarification_entry(cell, index, trial, meta, resume_script, grid_root)
    unless meta["session_id"].is_a?(String) && !meta["session_id"].empty?
      return blocked_entry(cell, index, "awaiting_review result has no recorded session ID", {"disposition" => "awaiting_review"}, trial)
    end
    budget = remaining_stage_budget(trial)
    return blocked_entry(cell, index, "cannot calculate cumulative stage budget: #{budget['error']}", {"disposition" => "awaiting_review"}, trial) if budget["error"]
    return blocked_entry(cell, index, "cumulative stage budget exhausted", {"disposition" => "awaiting_review"}, trial) unless budget.fetch("remaining").positive?
    stage_label = meta["stage"] == 2 ? "stage2" : "stage1"
    response = File.join(File.dirname(grid_root), "stage2-responses", format("%04d-%s-%s.txt", index + 1, stage_label, File.basename(trial)))
    assigned_root = assigned_cell_root(trial)
    continuations = Dir.glob(File.join(assigned_root, "continuations", "answer*"))
    next_answer = continuations.filter_map { |path| File.basename(path)[/\Aanswer(\d+)\z/, 1]&.to_i }.max.to_i + 1
    continuation = File.join(assigned_root, "continuations", "answer#{next_answer}")
    command = [RbConfig.ruby, resume_script, "--trial", trial, "--session-id", meta.fetch("session_id"),
               "--response-file", response, "--output", continuation, "--timeout", budget.fetch("remaining").to_s]
    {"grid_index" => index + 1, "cell" => cell, "status" => "clarification_required",
     "resume_source_trial" => trial, "response_file_to_prepare" => response,
     "continuation_output" => continuation, "command_argv" => command,
     "stage_budget_used_seconds" => budget.fetch("used"), "stage_budget_remaining_seconds" => budget.fetch("remaining"),
     "command" => Shellwords.join(command),
     "instruction" => "Inspect the transcript and write a reviewed response to response_file_to_prepare before running command_argv. This planner does not generate the response."}
  end

  def assigned_cell_root(trial)
    current = File.realpath(trial)
    seen = {}
    loop do
      raise "continuation cycle" if seen[current]
      seen[current] = true
      meta = read_json(File.join(current, "meta.json"))
      parent = meta["source_trial"]
      return current unless parent
      current = File.realpath(parent)
    end
  end

  def remaining_stage_budget(trial, limit: 900)
    target = read_json(File.join(trial, "meta.json"))
    target_stage = target["stage"] || 1
    current = File.realpath(trial)
    seen = {}
    runs = []
    loop do
      raise "continuation cycle" if seen[current]
      seen[current] = true
      meta = read_json(File.join(current, "meta.json"))
      stage = meta["stage"] || 1
      if stage == target_stage
        run = meta["agent_run"]
        seconds = run.is_a?(Hash) ? run["seconds"] : nil
        raise "agent execution seconds missing for #{current}" unless seconds.is_a?(Numeric) && seconds >= 0 && seconds.finite?
        runs << seconds
      end
      parent = meta["source_trial"]
      break unless parent
      current = File.realpath(parent)
    end
    used = runs.sum
    {"used" => used, "remaining" => [limit - used, 0].max}
  rescue StandardError => error
    {"error" => "#{error.class}: #{error.message}"}
  end

  def blocked_entry(cell, index, reason, source_record, source_trial = nil)
    {"grid_index" => index + 1, "cell" => cell, "status" => "blocked",
     "stage1_source_trial" => source_trial, "stage1_disposition" => source_record["disposition"],
     "reason" => reason}
  end

  def resolve_source(root, record)
    relative = record["final_path"]
    return nil unless relative.is_a?(String) && !relative.empty?
    path = File.expand_path(relative, root)
    path == root || path.start_with?(root + File::SEPARATOR) ? path : nil
  end

  def protocol_deviation_for(root, index)
    path = File.join(root, format("%04d", index + 1), "protocol-deviation.json")
    return nil unless File.file?(path)
    read_json(path)
  rescue StandardError
    {"error" => "protocol-deviation sidecar could not be read", "path" => path}
  end

  def validate_prepared(path, source, cell, kind)
    manifest = read_json(File.join(path, "stage2-manifest.json"))
    raise "prepared source differs" unless File.realpath(manifest.fetch("stage1_source_trial")) == source
    source_snapshot = read_json(File.join(source, "snapshot.json"))
    raise "prepared source final revision differs" unless manifest["stage1_final"] == source_snapshot.fetch("final")
    final_bundle = File.join(source, "final.bundle")
    raise "prepared source final bundle differs" unless manifest["stage1_final_bundle_sha256"] == Digest::SHA256.file(final_bundle).hexdigest
    raise "prepared task differs" unless manifest["task"] == cell["task"]
    raise "prepared condition differs" unless manifest["condition"] == cell["condition"]
    raise "prepared track differs" unless manifest["track"] == cell["track"]
    raise "prepared stage kind differs" unless manifest["stage_kind"] == kind
    manifest
  end

  def write_grid_sidecar(grid_root, category, index, object)
    write_json(File.join(grid_root, "stage2-#{category}", format("%04d.json", index + 1)), object)
  end

  def write_json(path, object)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(object) + "\n")
  end

  def read_json(path)
    JSON.parse(File.read(path))
  end

  def within?(path, parent)
    expanded_path = File.expand_path(path)
    expanded_parent = File.expand_path(parent)
    expanded_path == expanded_parent || expanded_path.start_with?(expanded_parent + File::SEPARATOR)
  end

  def cli
    options = {}
    OptionParser.new do |parser|
      %w[stage1-grid catalog output prepared-root stage-kind image runner resume-script].each do |key|
        parser.on("--#{key} VALUE") { |value| options[key.tr("-", "_")] = value }
      end
      parser.on("--resume") { options["resume"] = true }
    end.parse!
    raise "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
    %w[stage1_grid catalog output prepared_root stage_kind].each do |key|
      raise "--#{key.tr('_', '-')} required" if options[key].to_s.empty?
    end
    puts JSON.pretty_generate(prepare(**options.transform_keys(&:to_sym)))
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ContrastV2Grid.cli
  rescue StandardError => error
    warn "#{error.class}: #{error.message}"
    exit 2
  end
end
