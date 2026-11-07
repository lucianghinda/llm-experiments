#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"

module ContrastReviewBatch
  module_function

  PENDING = %w[running unstarted awaiting_review].freeze
  REVIEWABLE = %w[complete task_failure timeout].freeze
  TASK_CELLS = 24
  TRACK_CELLS = 12

  def build(grid_root:, stage:, task:, track:, contracts:, output:, grid_summary_path:, review_packets_path:,
            task_cells: TASK_CELLS, track_cells: TRACK_CELLS)
    raise "stage must be stage1 or stage2" unless %w[stage1 stage2].include?(stage)
    raise "track must be natural or specified" unless %w[natural specified].include?(track)
    root = File.realpath(grid_root)
    expanded_output = File.expand_path(output)
    raise "output parent directory must exist" unless Dir.exist?(File.dirname(expanded_output))
    destination = File.join(File.realpath(File.dirname(expanded_output)), File.basename(expanded_output))
    raise "output directory already exists: #{destination}" if File.exist?(destination)
    raise "output directory must be outside grid root" if within?(destination, root)
    require File.expand_path(grid_summary_path)
    require File.expand_path(review_packets_path)
    project_root = File.realpath(File.dirname(File.dirname(review_packets_path)))
    reports_root = File.join(project_root, "reports")
    protected_roots = [root, File.realpath(File.dirname(contracts)), File.realpath(File.dirname(grid_summary_path)),
                       File.realpath(File.dirname(review_packets_path))]
    if protected_roots.any? { |protected_root| within?(destination, protected_root) }
      raise "output directory must be outside grid, contract, and source inputs"
    end
    if within?(destination, project_root) && !within?(destination, reports_root)
      raise "output directory inside project must be under reports/"
    end

    grid = read_json(File.join(root, "grid.json"))
    assignments = grid.fetch("cells")
    summary = GridSummary.build(root)
    records = summary.fetch("cells")
    by_index = records.to_h { |record| [record.fetch("grid_index"), record] }
    task_assignments = assignments.each_with_index.filter_map do |cell, index|
      next unless cell["task"] == task
      record = by_index[index + 1]
      raise "GridSummary record missing for assigned task cell #{index + 1}" unless record
      {"grid_index" => index + 1, "cell" => cell, "record" => record}
    end
    raise "expected #{task_cells} assigned cells for #{task}; found #{task_assignments.length}" unless task_assignments.length == task_cells

    review_records = ReviewPackets.load_records(root)
    review_by_path = review_records.to_h { |record| [record[:path], record] }
    blocked = active_blocked_sidecars(root)
    deviations = operator_deviations(root, task_assignments)
    invalid_sources = stage == "stage2" ? invalid_stage2_sources(root, task_assignments, blocked) : {}
    gate_task_completion!(task_assignments, blocked, deviations)

    track_assignments = task_assignments.select { |entry| entry.dig("cell", "track") == track }
    raise "expected #{track_cells} #{track} assignments for #{task}; found #{track_assignments.length}" unless track_assignments.length == track_cells

    selected = []
    exclusions = []
    track_assignments.each do |entry|
      index = entry.fetch("grid_index")
      cell = entry.fetch("cell")
      summary_record = entry.fetch("record")
      if deviations.key?(index)
        exclusions << exclusion(entry, "operator protocol deviation", deviations[index]["sidecar_path"])
        next
      end
      if blocked.key?(index)
        exclusions << exclusion(entry, "explicitly blocked: #{blocked[index]['reason'] || 'source unavailable'}", blocked[index]["path"])
        next
      end
      if invalid_sources.key?(index)
        exclusions << exclusion(entry, "stage-1 source is an operator protocol deviation", invalid_sources[index])
        next
      end
      unless REVIEWABLE.include?(summary_record["disposition"])
        exclusions << exclusion(entry, "not reviewable disposition: #{summary_record['disposition']}")
        next
      end

      trial_path = final_trial_path(root, summary_record)
      trial = review_by_path[trial_path]
      unless trial
        exclusions << exclusion(entry, "final trial record missing", trial_path)
        next
      end

      eligibility = case summary_record["disposition"]
      when "complete"
        if summary_record["correctness"] != true
          "completed trial is not checker-correct"
        else
          trial[:validation]
        end
      when "task_failure", "timeout"
        ReviewPackets.stable_failure_validation(trial)
      end
      if eligibility
        exclusions << exclusion(entry, "not packet eligible: #{eligibility}", trial_path)
        next
      end
      selected << {"grid_index" => index, "cell" => cell, "trial_path" => trial_path,
                   "raw_disposition" => summary_record["disposition"]}
    end

    FileUtils.mkdir_p(destination)
    File.chmod(0o700, destination)
    final_list = File.join(destination, "final-trials.txt")
    File.open(final_list, "wx", 0o600) do |file|
      selected.each { |entry| file.puts(Pathname.new(entry.fetch("trial_path")).relative_path_from(Pathname.new(root))) }
    end
    packets_dir = File.join(destination, "review-packets")
    result = ReviewPackets.build(root, packets_dir, seed: 42, final_trials: final_list,
                                 contracts: contracts, include_stable_failures: true)
    summary_out = {
      "stage" => stage, "task" => task, "track" => track,
      "assigned_task_cells_before_track_filter" => task_assignments.length,
      "assigned_track_cells" => track_assignments.length,
      "selected_final_trials" => selected.length,
      "excluded_track_cells" => exclusions.length,
      "actual_packet_count" => result.fetch(:packet_count),
      "packet_builder_suppressed_count" => selected.length - result.fetch(:packet_count),
      "packet_builder_outcome_count" => result.fetch(:outcome_count),
      "operator_deviations_in_task" => deviations.length,
      "active_blocked_cells_in_task" => blocked.keys.count { |index| task_assignments.any? { |entry| entry["grid_index"] == index } },
      "output" => destination,
      "selected" => selected,
      "exclusions" => exclusions,
      "private_review_output" => packets_dir
    }
    File.write(File.join(destination, "batch-summary.json"), JSON.pretty_generate(summary_out) + "\n")
    File.chmod(0o600, File.join(destination, "batch-summary.json"))
    write_owner_notes(destination, summary_out)
    summary_out
  end

  def gate_task_completion!(entries, blocked, deviations)
    pending = entries.filter_map do |entry|
      index = entry.fetch("grid_index")
      disposition = entry.dig("record", "disposition")
      explicit_block = blocked.key?(index)
      operator_error = deviations.key?(index)
      [index, disposition] if PENDING.include?(disposition) && !explicit_block && !operator_error
    end
    return if pending.empty?

    details = pending.map { |index, disposition| "#{index}=#{disposition}" }.join(", ")
    raise "task batch is not ready: unresolved task assignments before track filtering: #{details}"
  end

  def active_blocked_sidecars(root)
    Dir.glob(File.join(root, "stage2-blocked", "*.json")).each_with_object({}) do |path, result|
      entry = read_json(path)
      next unless entry.is_a?(Hash) && entry["status"] == "blocked"
      index = entry["grid_index"]
      next unless index.is_a?(Integer)
      next if File.file?(File.join(root, format("%04d", index), "meta.json"))
      result[index] = entry.merge("path" => File.realpath(path))
    rescue JSON::ParserError => error
      raise "invalid blocked sidecar #{path}: #{error.message}"
    end
  end

  def operator_deviations(root, entries)
    entries.each_with_object({}) do |entry, result|
      index = entry.fetch("grid_index")
      path = File.join(root, format("%04d", index), "protocol-deviation.json")
      next unless File.file?(path)
      sidecar = read_json(path)
      result[index] = sidecar.merge("sidecar_path" => File.realpath(path)) if sidecar.is_a?(Hash) && sidecar["eligible_behavioral_trial"] == false
    rescue JSON::ParserError => error
      raise "invalid protocol deviation sidecar #{path}: #{error.message}"
    end
  end

  def invalid_stage2_sources(root, entries, blocked)
    entries.each_with_object({}) do |entry, result|
      index = entry.fetch("grid_index")
      meta_path = File.join(root, format("%04d", index), "meta.json")
      source = read_json(meta_path)["stage1_source_trial"] if File.file?(meta_path)
      source ||= blocked.dig(index, "stage1_source_trial")
      next unless source.is_a?(String) && File.directory?(source)
      deviation_path = File.join(source, "protocol-deviation.json")
      next unless File.file?(deviation_path)
      deviation = read_json(deviation_path)
      result[index] = File.realpath(deviation_path) if deviation.is_a?(Hash) && deviation["eligible_behavioral_trial"] == false
    rescue JSON::ParserError => error
      raise "invalid stage-1 protocol deviation sidecar #{deviation_path}: #{error.message}"
    end
  end

  def final_trial_path(root, record)
    relative = record["final_path"]
    raise "final trial path unknown for grid cell #{record['grid_index']}" unless relative.is_a?(String) && relative != "unknown"
    path = File.realpath(File.join(root, relative))
    raise "final trial escapes grid root" unless within?(path, root)
    path
  end

  def exclusion(entry, reason, path = nil)
    {"grid_index" => entry.fetch("grid_index"), "cell" => entry.fetch("cell"), "reason" => reason, "artifact_path" => path}
  end

  def write_owner_notes(output, summary)
    lines = ["# Private review batch selection", "", "Stage: #{summary['stage']}; task: #{summary['task']}; track: #{summary['track']}.",
      "", "Assigned before track filter: #{summary['assigned_task_cells_before_track_filter']}; assigned in selected track: #{summary['assigned_track_cells']}; selected final trials: #{summary['selected_final_trials']}; excluded: #{summary['excluded_track_cells']}; packet-builder suppressions: #{summary['packet_builder_suppressed_count']}; actual blinded packets: #{summary['actual_packet_count']}.",
      "", "## Exclusions", ""]
    summary.fetch("exclusions").each do |entry|
      cell = entry.fetch("cell")
      lines << "- Cell #{entry['grid_index']} (#{cell['agent']}, #{cell['condition']}, repeat #{cell['repeat']}): #{entry['reason']}#{entry['artifact_path'] ? " ([artifact](#{entry['artifact_path']}))" : ""}."
    end
    File.write(File.join(output, "owner-notes.md"), lines.join("\n") + "\n")
    File.chmod(0o600, File.join(output, "owner-notes.md"))
  end

  def within?(path, root)
    expanded_path = File.expand_path(path)
    expanded_root = File.expand_path(root)
    expanded_path == expanded_root || expanded_path.start_with?(expanded_root + File::SEPARATOR)
  end

  def read_json(path)
    JSON.parse(File.read(path))
  end

  def cli
    options = {}
    OptionParser.new do |parser|
      parser.banner = "ruby review_batch.rb --grid-root DIR --stage stage1|stage2 --task ID --track natural|specified --contracts FILE --output NEW_DIR --grid-summary FILE --review-packets FILE"
      parser.on("--grid-root DIR") { |value| options[:grid_root] = value }
      parser.on("--stage NAME") { |value| options[:stage] = value }
      parser.on("--task ID") { |value| options[:task] = value }
      parser.on("--track NAME") { |value| options[:track] = value }
      parser.on("--contracts FILE") { |value| options[:contracts] = value }
      parser.on("--output NEW_DIR") { |value| options[:output] = value }
      parser.on("--grid-summary FILE") { |value| options[:grid_summary_path] = value }
      parser.on("--review-packets FILE") { |value| options[:review_packets_path] = value }
    end.parse!
    %i[grid_root stage task track contracts output grid_summary_path review_packets_path].each do |key|
      raise "--#{key.to_s.tr('_', '-')} required" unless options[key]
    end
    puts JSON.pretty_generate(build(**options))
  end
end

ContrastReviewBatch.cli if $PROGRAM_NAME == __FILE__
