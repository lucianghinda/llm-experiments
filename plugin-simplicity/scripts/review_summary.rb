#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "pathname"

module ReviewSummary
  module_function

  RATERS = %w[luna terra].freeze
  BATCHES = %w[report csv_import].freeze
  DIMENSIONS = %w[concepts boundaries cohesion interfaces].freeze
  NOTE = "Automated review is a secondary view, not primary human truth. Score disagreements are preserved without adjudication. Correctness concerns are reviewer questions or uncovered-edge-case notes, not newly failed acceptance checks."

  def build(report_dir)
    root = File.realpath(report_dir)
    batch_names(root).map { |batch| summarize_batch(root, batch) }
  end

  def write(report_dir, output_dir)
    root = File.realpath(report_dir)
    output = File.expand_path(output_dir)
    raise "output directory already exists: #{output}" if File.exist?(output)

    batches = build(root)
    FileUtils.mkdir_p(File.dirname(output))
    Dir.mkdir(output, 0o700)
    begin
      findings = {"scope_note" => NOTE, "batches" => batches}
      File.write(File.join(output, "review-findings.json"), JSON.pretty_generate(findings) + "\n")
      File.write(File.join(output, "automated-review.md"), render(root, output, batches))
    rescue StandardError
      FileUtils.remove_entry(output) if File.exist?(output)
      raise
    end
    output
  end

  def batch_names(root)
    discovered_keys = Dir.glob(File.join(root, "review-*", "private-key.json")).filter_map do |path|
      File.basename(File.dirname(path)).delete_prefix("review-")
    end
    discovered_reviews = Dir.glob(File.join(root, "automated-review", "*-*.json")).filter_map do |path|
      match = File.basename(path).match(/\A(.+)-(?:#{RATERS.join("|")})\.json\z/)
      match && match[1]
    end
    (BATCHES + discovered_keys + discovered_reviews).uniq.sort_by { |batch| BATCHES.index(batch) || BATCHES.length }
  end

  def summarize_batch(root, batch)
    key_path = File.join(root, "review-#{batch}", "private-key.json")
    review_paths = RATERS.to_h { |rater| [rater, File.join(root, "automated-review", "#{batch}-#{rater}.json")] }
    present_review_paths = review_paths.select { |_rater, path| File.file?(path) }

    unless File.file?(key_path)
      raise "#{batch}: reviewer output exists without its packet mapping" unless present_review_paths.empty?

      return pending_batch(batch, "packet mapping has not been created")
    end

    mapping_file = read_json(key_path)
    packet_map = mapping_file.is_a?(Hash) ? mapping_file["packets"] : nil
    raise "#{batch}: private key has no packet map" unless packet_map.is_a?(Hash) && !packet_map.empty?

    expected_ids = packet_map.keys
    raise "#{batch}: duplicate expected packet IDs" unless expected_ids.uniq.length == expected_ids.length
    packet_dir = File.join(root, "review-#{batch}", "packets")
    expected_ids.each do |id|
      mapping = packet_map[id]
      raise "#{batch}: malformed mapping for #{id}" unless mapping.is_a?(Hash)
      packet = File.join(packet_dir, "#{id}.md")
      raise "#{batch}: blinded packet missing for #{id}" unless File.file?(packet)
    end

    reviewers = present_review_paths.to_h do |rater, path|
      [rater, read_ratings(path, rater, batch, expected_ids)]
    end
    complete = reviewers.keys.sort == RATERS.sort
    paired = complete ? paired_packets(root, batch, packet_map, reviewers) : []
    {
      "batch" => batch,
      "status" => complete ? "complete" : "pending_reviews",
      "mapping_path" => relative_link(root, key_path),
      "reviewer_files" => present_review_paths.transform_values { |path| relative_link(root, path) },
      "expected_reviewers" => RATERS,
      "missing_reviewers" => RATERS - reviewers.keys,
      "expected_packet_count" => expected_ids.length,
      "reviewers" => reviewers,
      "packets" => paired,
      "dimension_agreement" => complete ? agreement_summary(paired) : {},
      "cell_groups" => complete ? cell_group_summary(paired) : []
    }
  end

  def pending_batch(batch, reason)
    {
      "batch" => batch,
      "status" => "pending_reviews",
      "pending_reason" => reason,
      "expected_reviewers" => RATERS,
      "missing_reviewers" => RATERS,
      "expected_packet_count" => "unknown",
      "reviewers" => {},
      "packets" => [],
      "dimension_agreement" => {},
      "cell_groups" => []
    }
  end

  def read_ratings(path, rater, batch, expected_ids)
    data = read_json(path)
    raise "#{path}: rating file must be an object" unless data.is_a?(Hash)
    raise "#{path}: batch mismatch" unless data["batch"] == batch
    raise "#{path}: reviewer mismatch" unless data["reviewer"] == rater
    ratings = data["ratings"]
    raise "#{path}: ratings must be an array" unless ratings.is_a?(Array)

    ids = ratings.map do |rating|
      raise "#{path}: malformed rating row" unless rating.is_a?(Hash) && rating["packet"].is_a?(String)

      rating["packet"]
    end
    raise "#{path}: duplicate packet ratings" unless ids.uniq.length == ids.length
    missing = expected_ids - ids
    unexpected = ids - expected_ids
    raise "#{path}: missing packet IDs #{missing.join(", ")}" unless missing.empty?
    raise "#{path}: unexpected packet IDs #{unexpected.join(", ")}" unless unexpected.empty?

    ratings.to_h do |rating|
      id = rating.fetch("packet")
      scores = DIMENSIONS.to_h do |dimension|
        score = rating[dimension]
        raise "#{path}: #{id} #{dimension} must be an integer from 1 to 5" unless score.is_a?(Integer) && (1..5).cover?(score)

        [dimension, score]
      end
      evidence = rating["evidence"]
      raise "#{path}: #{id} evidence must be an object" unless evidence.is_a?(Hash)
      evidence_values = DIMENSIONS.to_h do |dimension|
        value = evidence[dimension]
        raise "#{path}: #{id} #{dimension} evidence must be nonempty text" unless value.is_a?(String) && !value.strip.empty?

        [dimension, value]
      end
      concerns = rating.fetch("correctness_concerns", [])
      raise "#{path}: #{id} correctness_concerns must be an array of strings" unless concerns.is_a?(Array) && concerns.all? { |value| value.is_a?(String) }
      [id, {"scores" => scores, "evidence" => evidence_values, "correctness_concerns" => concerns}]
    end
  end

  def paired_packets(root, batch, packet_map, reviewers)
    ids = packet_map.keys.sort
    ids.map do |id|
      mapping = packet_map.fetch(id)
      luna = reviewers.fetch("luna").fetch(id)
      terra = reviewers.fetch("terra").fetch(id)
      differences = DIMENSIONS.to_h do |dimension|
        [dimension, luna.dig("scores", dimension) - terra.dig("scores", dimension)]
      end
      {
        "packet" => id,
        "cell" => mapping.slice("grid_cell", "final_trial", "task", "agent", "condition", "track"),
        "packet_path" => relative_link(root, File.join(root, "review-#{batch}", "packets", "#{id}.md")),
        "cell_path" => cell_path(root, mapping["grid_cell"]),
        "workspace_path" => workspace_path(root, mapping["final_trial"], mapping["grid_cell"]),
        "source_index_path" => File.file?(File.join(root, "code-index.md")) ? relative_link(root, File.join(root, "code-index.md")) : "unknown",
        "reviewers" => {"luna" => luna, "terra" => terra},
        "score_difference_luna_minus_terra" => differences,
        "correctness_concerns" => {
          "luna" => luna["correctness_concerns"],
          "terra" => terra["correctness_concerns"]
        }
      }
    end
  end

  def agreement_summary(packets)
    DIMENSIONS.to_h do |dimension|
      differences = packets.map { |packet| packet.dig("score_difference_luna_minus_terra", dimension).abs }
      exact = differences.count(&:zero?)
      [dimension, {
        "paired_packet_count" => differences.length,
        "exact_agreement_count" => exact,
        "mean_absolute_disagreement" => differences.empty? ? "unknown" : differences.sum.to_f / differences.length
      }]
    end
  end

  def cell_group_summary(packets)
    packets.group_by do |packet|
      cell = packet.fetch("cell")
      %w[task agent track condition].map { |key| cell[key] }
    end.sort_by { |key, _| key.map(&:to_s) }.map do |(task, agent, track, condition), group|
      per_rater = RATERS.to_h do |rater|
        [rater, DIMENSIONS.to_h do |dimension|
          values = group.map { |packet| packet.dig("reviewers", rater, "scores", dimension) }.compact.sort
          [dimension, {"sample_count" => values.length, "median" => median(values)}]
        end]
      end
      {
        "task" => task,
        "agent" => agent,
        "track" => track,
        "condition" => condition,
        "packet_count" => group.length,
        "per_rater_dimension_medians" => per_rater
      }
    end
  end

  def median(values)
    return "unknown" if values.empty?

    middle = values.length / 2
    values.length.odd? ? values[middle] : (values[middle - 1] + values[middle]) / 2.0
  end

  def cell_path(root, grid_cell)
    results_root = File.expand_path("../../results-raw/#{File.basename(root)}", root)
    path = safe_path(results_root, grid_cell)
    path && File.exist?(path) ? relative_link(root, path) : "unknown"
  end

  def workspace_path(root, final_trial, grid_cell)
    results_root = File.expand_path("../../results-raw/#{File.basename(root)}", root)
    trial = safe_path(results_root, final_trial)
    recorded_workspace = if trial
      metadata_path = File.join(trial, "meta.json")
      metadata = File.file?(metadata_path) ? (read_json(metadata_path) || {}) : {}
      safe_path(results_root, metadata["workspace_path"])
    end
    cell = safe_path(results_root, grid_cell)
    workspace = [recorded_workspace, cell && File.join(cell, "workspace")].find { |path| path && File.directory?(path) }
    workspace ? relative_link(root, workspace) : "unknown"
  end

  def safe_path(root, relative)
    return nil unless relative.is_a?(String) && !relative.empty?

    path = File.expand_path(relative, root)
    prefix = root.end_with?(File::SEPARATOR) ? root : root + File::SEPARATOR
    path.start_with?(prefix) ? path : nil
  end

  def render(report_root, output, batches)
    lines = [
      "# Automated secondary review summary",
      "",
      NOTE,
      "",
      "Dimension scores are reported separately. No combined score, rank, or winner is produced. Correctness concerns below are reviewer questions or uncovered-edge-case notes, not failed acceptance checks.",
      ""
    ]
    batches.each do |batch|
      lines << "## #{batch.fetch("batch")}: #{batch.fetch("status").tr("_", " ")}" 
      lines << ""
      if batch["pending_reason"]
        lines << "Pending: #{batch["pending_reason"]}."
        lines << ""
        next
      end
      lines << "Expected packets: #{batch.fetch("expected_packet_count")}; reviewers received: #{(RATERS - batch.fetch("missing_reviewers")).join(", ")}."
      if batch["missing_reviewers"].any?
        lines << "Pending reviewers: #{batch.fetch("missing_reviewers").join(", ")}."
        lines << ""
        next
      end
      batch.fetch("reviewer_files").each { |rater, path| lines << "- #{rater} ratings: [source JSON](#{relative_output_link(output, report_root, path)})" }
      lines << "- Packet mapping: [private key](#{relative_output_link(output, report_root, batch.fetch("mapping_path"))})"
      lines << ""
      lines << "### Dimension agreement"
      lines << ""
      lines << "| Dimension | Paired packets | Exact agreement | Mean absolute disagreement |"
      lines << "|---|---:|---:|---:|"
      batch.fetch("dimension_agreement").each do |dimension, values|
        lines << "| #{dimension} | #{values.fetch("paired_packet_count")} | #{values.fetch("exact_agreement_count")} | #{format_value(values.fetch("mean_absolute_disagreement"))} |"
      end
      lines << ""
      lines << "### Per-packet ratings and evidence"
      lines << ""
      batch.fetch("packets").each do |packet|
        lines << "#### #{packet.fetch("packet")}: #{packet.dig("cell", "task")} / #{packet.dig("cell", "agent")} / #{packet.dig("cell", "track")} / #{packet.dig("cell", "condition")}"
        lines << ""
        lines << "Packet: [#{packet.fetch("packet")}.md](#{relative_output_link(output, report_root, packet.fetch("packet_path"))}); cell: #{link_or_unknown(output, report_root, packet.fetch("cell_path"))}; workspace: #{link_or_unknown(output, report_root, packet.fetch("workspace_path"))}; source index: #{link_or_unknown(output, report_root, packet.fetch("source_index_path"))}."
        lines << ""
        lines << "| Dimension | Luna | Terra | Luna − Terra |"
        lines << "|---|---:|---:|---:|"
        DIMENSIONS.each do |dimension|
          luna = packet.dig("reviewers", "luna", "scores", dimension)
          terra = packet.dig("reviewers", "terra", "scores", dimension)
          lines << "| #{dimension} | #{luna} | #{terra} | #{packet.dig("score_difference_luna_minus_terra", dimension)} |"
        end
        lines << ""
        RATERS.each do |rater|
          lines << "**#{rater.capitalize} evidence**"
          lines << ""
          DIMENSIONS.each { |dimension| lines << "- #{dimension}: #{escape(packet.dig("reviewers", rater, "evidence", dimension))}" }
          concerns = packet.dig("correctness_concerns", rater)
          lines << "- Review questions / uncovered edge cases: #{concerns.empty? ? "none recorded" : escape(concerns.join("; "))}"
          lines << ""
        end
      end
      lines << "### Per-cell group medians"
      lines << ""
      batch.fetch("cell_groups").each do |group|
        lines << "#### #{group.values_at("task", "agent", "track", "condition").join(" / ")} (n=#{group.fetch("packet_count")})"
        lines << ""
        lines << "| Reviewer | Concepts | Boundaries | Cohesion | Interfaces |"
        lines << "|---|---:|---:|---:|---:|"
        RATERS.each do |rater|
          metrics = group.dig("per_rater_dimension_medians", rater)
          vals = DIMENSIONS.map { |dimension| m = metrics.fetch(dimension); "#{format_value(m.fetch("median"))} (n=#{m.fetch("sample_count")})" }
          lines << "| #{rater.capitalize} | #{vals.join(" | ")} |"
        end
        lines << ""
      end
    end
    lines.join("\n") + "\n"
  end

  def relative_link(report_root, path)
    Pathname.new(path).relative_path_from(Pathname.new(report_root)).to_s
  end

  def relative_output_link(output, report_root, path)
    return "unknown" if path == "unknown"

    Pathname.new(File.expand_path(path, report_root)).relative_path_from(Pathname.new(output)).to_s
  end

  def link_or_unknown(output, report_root, path)
    path == "unknown" ? "unknown" : "[open](#{relative_output_link(output, report_root, path)})"
  end

  def read_json(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => error
    raise "invalid JSON #{path}: #{error.message}"
  end

  def format_value(value)
    value.nil? ? "unknown" : value.to_s
  end

  def escape(value)
    format_value(value).gsub("|", "\\|").gsub("\n", " ")
  end
end

if $PROGRAM_NAME == __FILE__
  output_dir = nil
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/review_summary.rb REPORT_DIR --output OUTPUT_DIR"
    opts.on("--output DIR", "New directory for derived review files") { |value| output_dir = value }
  end
  begin
    parser.parse!
    abort parser.to_s unless ARGV.length == 1 && output_dir
    output = ReviewSummary.write(ARGV.fetch(0), output_dir)
    puts "Wrote derived review summary to #{output}"
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
