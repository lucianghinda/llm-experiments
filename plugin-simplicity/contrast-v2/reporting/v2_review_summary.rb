#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"

module V2ReviewSummary
  module_function

  STAGES = %w[stage1 stage2].freeze
  TASKS = %w[notification regional export].freeze
  TRACKS = %w[natural specified].freeze
  RATERS = %w[luna_a luna_b].freeze
  DIMENSIONS = %w[concepts boundaries cohesion interfaces].freeze
  NOTE = "Automated review is a secondary perspective. Correctness concerns are reviewer questions or uncovered-edge-case notes, not failed acceptance checks. Dimensions and raters are summarized separately; no weighted score, rank, or winner is produced."

  def batches
    STAGES.product(TASKS, TRACKS).map { |stage, task, track| "#{stage}-#{task}-#{track}" }
  end

  def build(report_root)
    root = File.realpath(report_root)
    batches.map { |batch| summarize_batch(root, batch) }
  end

  def write(report_root, output)
    root = File.realpath(report_root)
    expanded = File.expand_path(output)
    raise "output parent directory must exist" unless Dir.exist?(File.dirname(expanded))
    destination = File.join(File.realpath(File.dirname(expanded)), File.basename(expanded))
    raise "output directory already exists: #{destination}" if File.exist?(destination)
    raise "output directory must be outside report inputs" if within?(destination, root)

    summary = {"scope_note" => NOTE, "batches" => build(root)}
    Dir.mkdir(destination, 0o700)
    begin
      json_path = File.join(destination, "v2-review-summary.json")
      markdown_path = File.join(destination, "v2-review-summary.md")
      File.write(json_path, JSON.pretty_generate(summary) + "\n", mode: "w", perm: 0o600)
      File.write(markdown_path, render(destination, root, summary), mode: "w", perm: 0o600)
    rescue StandardError
      FileUtils.remove_entry(destination) if File.exist?(destination)
      raise
    end
    destination
  end

  def summarize_batch(root, batch)
    packet_root = File.join(root, "review-#{batch}", "review-packets")
    key_path = File.join(packet_root, "private-key.json")
    reviewer_paths = RATERS.to_h { |rater| [rater, File.join(root, "automated-review", "#{batch}-#{rater}.json")] }
    existing_reviews = reviewer_paths.select { |_rater, path| File.file?(path) }
    selection_path = File.join(root, "review-#{batch}", "batch-summary.json")
    selection = File.file?(selection_path) ? read_json(selection_path) : nil
    exclusions = if selection.is_a?(Hash) && selection["exclusions"].is_a?(Array)
      {"count" => selection["exclusions"].length,
       "reasons" => selection["exclusions"].group_by { |row| row["reason"] || "unknown" }.transform_values(&:length),
       "source_path" => relative(root, selection_path)}
    else
      {"count" => "unknown", "reasons" => {}, "source_path" => File.file?(selection_path) ? relative(root, selection_path) : "unknown"}
    end
    unless File.file?(key_path)
      return pending(batch, existing_reviews.empty? ? "packet mapping missing" : "packet mapping missing; reviewer file(s) cannot be joined").merge("exclusions" => exclusions)
    end

    mapping = read_json(key_path)
    packet_map = mapping.is_a?(Hash) ? mapping["packets"] : nil
    raise "#{batch}: private key missing packets map" unless packet_map.is_a?(Hash) && !packet_map.empty?
    packet_map.each do |id, entry|
      raise "#{batch}: malformed private-key row #{id}" unless id.match?(/\AR-\d{4}\z/) && entry.is_a?(Hash)
      packet_path = File.join(packet_root, "packets", "#{id}.md")
      raise "#{batch}: missing blinded packet #{packet_path}" unless File.file?(packet_path)
    end

    ratings = existing_reviews.to_h do |rater, path|
      [rater, read_ratings(path, batch, rater, packet_map.keys)]
    end
    paired = (ratings.keys.sort == RATERS.sort)
    packets = packet_map.keys.sort.map do |id|
      per_rater = RATERS.each_with_object({}) { |rater, result| result[rater] = ratings.dig(rater, id) if ratings.key?(rater) }
      gaps = paired ? DIMENSIONS.to_h { |dimension| [dimension, per_rater.fetch("luna_a").dig("scores", dimension) - per_rater.fetch("luna_b").dig("scores", dimension)] } : {}
      {
        "packet" => id,
        "cell" => packet_map.fetch(id).slice("grid_cell", "final_trial", "task", "agent", "condition", "track"),
        "packet_path" => relative(root, File.join(packet_root, "packets", "#{id}.md")),
        "reviewer_source_paths" => existing_reviews.transform_values { |path| relative(root, path) },
        "reviewers" => per_rater,
        "score_difference_luna_a_minus_luna_b" => gaps,
        "correctness_concerns" => per_rater.transform_values { |row| row.fetch("correctness_concerns") }
      }
    end
    {
      "batch" => batch,
      "status" => paired ? "complete" : "pending_reviews",
      "mapping_path" => relative(root, key_path),
      "reviewer_files" => existing_reviews.transform_values { |path| relative(root, path) },
      "expected_reviewers" => RATERS,
      "missing_reviewers" => RATERS - ratings.keys,
      "expected_packet_count" => packet_map.length,
      "exclusions" => exclusions,
      "packets" => packets,
      "dimension_agreement" => paired ? agreement(packets) : {},
      "cell_groups" => cell_groups(packets)
    }
  end

  def pending(batch, reason)
    {"batch" => batch, "status" => "pending_reviews", "pending_reason" => reason,
     "expected_reviewers" => RATERS, "missing_reviewers" => RATERS, "expected_packet_count" => "unknown",
     "reviewers" => {}, "packets" => [], "dimension_agreement" => {}, "cell_groups" => []}
  end

  def read_ratings(path, batch, rater, expected_ids)
    data = read_json(path)
    raise "#{path}: reviewer output must be an object" unless data.is_a?(Hash)
    raise "#{path}: batch mismatch" unless data["batch"] == batch
    raise "#{path}: reviewer mismatch" unless data["reviewer"] == rater
    rows = data["ratings"]
    raise "#{path}: ratings must be an array" unless rows.is_a?(Array)
    ids = rows.map { |row| row.is_a?(Hash) && row["packet"].is_a?(String) ? row["packet"] : (raise "#{path}: malformed rating row") }
    raise "#{path}: duplicate packet IDs" unless ids.uniq.length == ids.length
    raise "#{path}: missing packet IDs #{(expected_ids - ids).join(', ')}" unless (expected_ids - ids).empty?
    raise "#{path}: unexpected packet IDs #{(ids - expected_ids).join(', ')}" unless (ids - expected_ids).empty?
    rows.to_h do |row|
      id = row.fetch("packet")
      scores = DIMENSIONS.to_h do |dimension|
        value = row[dimension]
        raise "#{path}: #{id} #{dimension} must be integer 1..5" unless value.is_a?(Integer) && (1..5).cover?(value)
        [dimension, value]
      end
      evidence = row["evidence"]
      raise "#{path}: #{id} evidence must be an object" unless evidence.is_a?(Hash)
      evidence = DIMENSIONS.to_h do |dimension|
        value = evidence[dimension]
        raise "#{path}: #{id} #{dimension} evidence missing" unless value.is_a?(String) && !value.strip.empty?
        [dimension, value]
      end
      concerns = row.fetch("correctness_concerns", [])
      raise "#{path}: #{id} correctness_concerns must be strings" unless concerns.is_a?(Array) && concerns.all? { |value| value.is_a?(String) }
      [id, {"scores" => scores, "evidence" => evidence, "correctness_concerns" => concerns}]
    end
  end

  def agreement(packets)
    DIMENSIONS.to_h do |dimension|
      gaps = packets.map { |packet| packet.fetch("score_difference_luna_a_minus_luna_b").fetch(dimension).abs }
      [dimension, {"paired_packet_count" => gaps.length, "exact_agreement_count" => gaps.count(&:zero?),
                   "mean_absolute_disagreement" => gaps.empty? ? "unknown" : gaps.sum.to_f / gaps.length}]
    end
  end

  def cell_groups(packets)
    packets.group_by do |packet|
      cell = packet.fetch("cell")
      %w[task agent track condition].map { |key| cell[key] }
    end.sort_by { |key, _| key.map(&:to_s) }.map do |(task, agent, track, condition), group|
      per_rater = RATERS.to_h do |rater|
        dimensions = DIMENSIONS.to_h do |dimension|
          values = group.filter_map { |packet| packet.dig("reviewers", rater, "scores", dimension) }.sort
          [dimension, {"sample_count" => values.length, "median" => median(values)}]
        end
        [rater, dimensions]
      end
      {"task" => task, "agent" => agent, "track" => track, "condition" => condition,
       "packet_count" => group.length, "per_rater_dimension" => per_rater}
    end
  end

  def median(values)
    return "unknown" if values.empty?
    middle = values.length / 2
    values.length.odd? ? values[middle] : (values[middle - 1] + values[middle]) / 2.0
  end

  def render(output, report_root, summary)
    lines = ["# V2 automated review summary", "", NOTE, "", "| Batch | Status | Packets | Reviewers pending |", "|---|---|---:|---|"]
    summary.fetch("batches").each do |batch|
      lines << "| #{batch.fetch('batch')} | #{batch.fetch('status')} | #{batch.fetch('expected_packet_count')} | #{batch.fetch('missing_reviewers').join(', ')} |"
    end
    summary.fetch("batches").each do |batch|
      lines << ""
      lines << "## #{batch.fetch('batch')} — #{batch.fetch('status')}"
      lines << ""
      exclusion = batch["exclusions"]
      if exclusion
        count = exclusion.fetch("count")
        source = exclusion.fetch("source_path")
        lines << "Packet-selection exclusions: #{count}#{source == 'unknown' ? '' : " ([source batch summary](#{rel_link(output, report_root, source)}))"}."
      end
      if batch["pending_reason"]
        lines << "Pending: #{batch.fetch('pending_reason')}."
        next
      end
      lines << "Packet map: [private key](#{rel_link(output, report_root, batch.fetch('mapping_path'))}); reviewer JSON: #{batch.fetch('reviewer_files').map { |rater, path| "[#{rater}](#{rel_link(output, report_root, path)})" }.join(', ')}."
      lines << ""
      if batch.fetch("missing_reviewers").any?
        lines << "Pending reviewers: #{batch.fetch('missing_reviewers').join(', ')}."
        lines << ""
      end
      unless batch.fetch("dimension_agreement").empty?
        lines << "| Dimension | Paired n | Exact agreement | Mean absolute gap |"
        lines << "|---|---:|---:|---:|"
        batch.fetch("dimension_agreement").each do |dimension, values|
          lines << "| #{dimension} | #{values.fetch('paired_packet_count')} | #{values.fetch('exact_agreement_count')} | #{values.fetch('mean_absolute_disagreement')} |"
        end
        lines << ""
      end
      batch.fetch("cell_groups").each do |group|
        lines << "### #{group.values_at('task', 'agent', 'track', 'condition').join(' / ')} (packets n=#{group.fetch('packet_count')})"
        lines << ""
        lines << "| Rater | Dimension | n | Median |"
        lines << "|---|---|---:|---:|"
        RATERS.each do |rater|
          DIMENSIONS.each do |dimension|
            metric = group.dig("per_rater_dimension", rater, dimension)
            lines << "| #{rater} | #{dimension} | #{metric.fetch('sample_count')} | #{metric.fetch('median')} |"
          end
        end
        lines << ""
      end
      batch.fetch("packets").each do |packet|
        cell = packet.fetch("cell")
        lines << "### #{packet.fetch('packet')} — #{[cell['task'], cell['agent'], cell['track'], cell['condition']].join(' / ')}"
        lines << ""
        lines << "Packet: [source](#{rel_link(output, report_root, packet.fetch('packet_path'))}); final trial: #{cell['final_trial'] || 'unknown'}; grid cell: #{cell['grid_cell'] || 'unknown'}."
        lines << ""
        lines << "| Dimension | luna_a | luna_b | Gap (a − b) |"
        lines << "|---|---:|---:|---:|"
        DIMENSIONS.each do |dimension|
          a = packet.dig("reviewers", "luna_a", "scores", dimension) || "pending"
          b = packet.dig("reviewers", "luna_b", "scores", dimension) || "pending"
          gap = packet.dig("score_difference_luna_a_minus_luna_b", dimension) || "pending"
          lines << "| #{dimension} | #{a} | #{b} | #{gap} |"
        end
        RATERS.each do |rater|
          reviewer = packet.dig("reviewers", rater)
          next unless reviewer
          lines << ""
          lines << "**#{rater} evidence**"
          DIMENSIONS.each { |dimension| lines << "- #{dimension}: #{escape(reviewer.dig('evidence', dimension))}" }
          concerns = reviewer.fetch("correctness_concerns")
          lines << "- Review questions / uncovered edges (not acceptance failures): #{concerns.empty? ? 'none recorded' : escape(concerns.join('; '))}"
        end
        lines << ""
      end
    end
    lines.join("\n") + "\n"
  end

  def rel_link(output, report_root, path)
    target = Pathname.new(File.expand_path(path, report_root))
    target.relative_path_from(Pathname.new(output)).to_s
  end

  def relative(root, path)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  end

  def within?(path, root)
    candidate = File.expand_path(path)
    base = File.expand_path(root)
    candidate == base || candidate.start_with?(base + File::SEPARATOR)
  end

  def read_json(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => error
    raise "invalid JSON #{path}: #{error.message}"
  end

  def escape(value)
    value.to_s.gsub("|", "\\|").gsub("\n", " ")
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    OptionParser.new do |parser|
      parser.banner = "ruby v2_review_summary.rb REPORT_ROOT --output NEW_DIR"
      parser.on("--output DIR") { |value| options[:output] = value }
    end.parse!
    abort "REPORT_ROOT and --output are required" unless ARGV.length == 1 && options[:output]
    puts V2ReviewSummary.write(ARGV.fetch(0), options.fetch(:output))
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
