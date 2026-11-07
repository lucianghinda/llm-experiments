#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

module PilotReport
  module_function

  TOKEN_FIELDS = %w[input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens].freeze

  def build(results_root)
    root = File.expand_path(results_root)
    raise "results directory missing: #{root}" unless Dir.exist?(root)

    trials = Dir.glob(File.join(root, "**", "meta.json")).sort.reject do |meta_path|
      Pathname.new(meta_path).relative_path_from(Pathname.new(root)).each_filename.include?("verification-attempts")
    end.map do |meta_path|
      trial = File.dirname(meta_path)
      relative = Pathname.new(trial).relative_path_from(Pathname.new(root)).to_s
      report_trial(relative, trial)
    end

    render(trials)
  end

  def report_trial(relative, trial)
    meta = read_json(File.join(trial, "meta.json")) || {}
    incident = read_json(File.join(trial, "incident.json"))
    snapshot = read_json(File.join(trial, "snapshot.json"))
    checks = read_json(File.join(trial, "checks.json"))
    agent_run = meta["agent_run"].is_a?(Hash) ? meta["agent_run"] : {}
    usage = usage_from(File.join(trial, "transcript.txt"), meta["agent"])
    changes = snapshot ? diff_summary(trial, snapshot) : unknown_changes("snapshot missing")
    fake = meta["adapter"] == "fake" || meta["status"].to_s.start_with?("fake_")
    check_result = check_summary(checks)

    {
      path: relative,
      task: meta["task"],
      agent: meta["agent"],
      model: meta["model"],
      condition: meta["condition"],
      track: meta["track"],
      status: meta["status"],
      eligibility: eligibility(meta, relative, incident),
      incident: incident && incident["classification"],
      fake: fake,
      checks: check_result,
      restoration: meta.fetch("restoration_verified", nil),
      seconds: number_or_unknown(agent_run["seconds"]),
      usage: usage,
      changes: changes.fetch(:counts),
      change_error: changes[:error]
    }
  rescue StandardError => error
    {
      path: relative,
      status: meta && meta["status"],
      task: meta && meta["task"],
      agent: meta && meta["agent"],
      model: meta && meta["model"],
      condition: meta && meta["condition"],
      track: meta && meta["track"],
      eligibility: meta ? eligibility(meta, relative, incident) : "unknown",
      incident: incident && incident["classification"],
      restoration: meta && meta.fetch("restoration_verified", nil),
      checks: "unknown",
      fake: meta ? (meta["adapter"] == "fake" || meta["status"].to_s.start_with?("fake_")) : false,
      seconds: "unknown",
      usage: unknown_usage,
      changes: unknown_changes("report error: #{error.class}")[:counts],
      change_error: "report error: #{error.class}"
    }
  end

  def eligibility(meta, relative, incident = nil)
    return "excluded (fake adapter)" if meta["adapter"] == "fake" || meta["status"].to_s.start_with?("fake_")
    return "excluded (infrastructure incident)" if incident && incident["eligible_behavioral_trial"] == false
    return "part of existing cell (continuation; not an additional trial)" if relative.include?("/continuations/")
    return "excluded (continuation/audit)" if meta["task"] == "continuation_smoke"
    return "excluded (setup failure)" if %w[infrastructure_failure setup_failure].include?(meta["status"])

    "behavioral attempt"
  end

  def check_summary(checks)
    return "unknown" unless checks.is_a?(Array)

    passed = checks.count { |check| check.is_a?(Hash) && check["exit"] == 0 && !check["timed_out"] }
    "#{passed}/#{checks.length} passed"
  end

  def usage_from(path, agent)
    return unknown_usage unless File.file?(path)

    events = File.foreach(path).filter_map do |line|
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    case agent
    when "claude" then claude_usage(events)
    when "codex" then codex_usage(events)
    else unknown_usage
    end
  rescue StandardError
    unknown_usage
  end

  # Claude's result event is the aggregate for the turn. Per-message usage
  # events are intentionally ignored to avoid counting the same tokens twice.
  def claude_usage(events)
    result = events.reverse.find { |event| event.is_a?(Hash) && event["type"] == "result" }
    return unknown_usage unless result

    usage = result["usage"].is_a?(Hash) ? result["usage"] : {}
    {
      input_tokens: number_or_unknown(usage["input_tokens"]),
      output_tokens: number_or_unknown(usage["output_tokens"]),
      cache_read_input_tokens: number_or_unknown(usage["cache_read_input_tokens"]),
      cache_creation_input_tokens: number_or_unknown(usage["cache_creation_input_tokens"]),
      cost_usd: number_or_unknown(result["total_cost_usd"])
    }
  end

  # Codex emits per-turn aggregates. Sum a field only when every completed
  # turn contains it; other events may include partial usage for that turn.
  # Codex input_tokens already includes cached input. Cache fields are subsets,
  # not additive totals, and Claude reports cache categories separately.
  def codex_usage(events)
    completed = events.select { |event| event.is_a?(Hash) && event["type"] == "turn.completed" }
    return unknown_usage if completed.empty?

    fields = {
      input_tokens: %w[input_tokens],
      output_tokens: %w[output_tokens],
      cache_read_input_tokens: %w[cached_input_tokens cache_read_input_tokens],
      cache_creation_input_tokens: %w[cache_write_input_tokens cache_creation_input_tokens]
    }
    totals = fields.to_h do |target, candidates|
      values = completed.filter_map do |event|
        usage = event["usage"]
        candidates.lazy.map { |field| usage[field] if usage.is_a?(Hash) }.find { |value| value.is_a?(Numeric) }
      end
      [target, values.length == completed.length ? values.sum : "unknown"]
    end
    totals.merge(cost_usd: "unknown")
  end

  def diff_summary(trial, snapshot)
    return unknown_changes("snapshot missing baseline/final revisions") unless snapshot["baseline"] && snapshot["final"]

    Dir.mktmpdir("pilot-report") do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p(repo)
      git(repo, "init", "-q")
      # Fetching bundles can otherwise start background auto maintenance that
      # races Dir.mktmpdir cleanup and leaves .git/objects non-empty.
      git(repo, "config", "gc.auto", "0")
      git(repo, "config", "maintenance.auto", "false")
      %w[baseline final].each do |version|
        bundle = File.join(trial, "#{version}.bundle")
        return unknown_changes("#{version} bundle missing") unless File.file?(bundle)

        git(repo, "fetch", bundle, "refs/pilot/#{version}:refs/pilot/#{version}")
      end
      baseline = git(repo, "rev-parse", "refs/pilot/baseline").strip
      final = git(repo, "rev-parse", "refs/pilot/final").strip
      unless baseline == snapshot["baseline"] && final == snapshot["final"]
        return unknown_changes("bundle revisions do not match snapshot")
      end

      statuses = git(repo, "diff", "--no-renames", "--name-status", baseline, final).lines
      numstats = git(repo, "diff", "--no-renames", "--numstat", baseline, final).lines
      summary = empty_changes

      statuses.each do |line|
        status, path = line.chomp.split("\t", 2)
        bucket = category(path)
        summary[bucket][:added_files] += 1 if status == "A"
        summary[bucket][:deleted_files] += 1 if status == "D"
        summary[bucket][:modified_files] += 1 if status == "M"
      end

      numstats.each do |line|
        added, deleted, path = line.chomp.split("\t", 3)
        next unless added&.match?(/\A\d+\z/) && deleted&.match?(/\A\d+\z/)

        bucket = category(path)
        summary[bucket][:added_lines] += added.to_i
        summary[bucket][:deleted_lines] += deleted.to_i
      end

      {counts: summary, error: nil}
    end
  rescue StandardError => error
    unknown_changes("#{error.class}: #{error.message.lines.first.to_s.strip}")
  end

  def category(path)
    normalized = path.to_s.downcase
    return :tests if normalized.start_with?("test/", "tests/", "spec/") || File.basename(normalized).start_with?("test_") || normalized.match?(%r{(?:^|/)[^/]+_(?:test|spec)\.[^/]+\z})
    return :docs if normalized.start_with?("docs/", "doc/") || normalized.match?(%r{(?:^|/)(?:readme|changelog|contributing|license)(?:\.[^/]*)?\z}) || normalized.match?(/\.(?:md|mdx|rst|adoc)\z/)

    :production
  end

  def empty_changes
    %i[production tests docs].to_h do |bucket|
      [bucket, {added_files: 0, deleted_files: 0, modified_files: 0, added_lines: 0, deleted_lines: 0}]
    end
  end

  def unknown_changes(error)
    counts = %i[production tests docs].to_h do |bucket|
      [bucket, {added_files: "unknown", deleted_files: "unknown", modified_files: "unknown", added_lines: "unknown", deleted_lines: "unknown"}]
    end
    {counts: counts, error: error}
  end

  def unknown_usage
    TOKEN_FIELDS.to_h { |field| [field.to_sym, "unknown"] }.merge(cost_usd: "unknown")
  end

  def number_or_unknown(value)
    value.is_a?(Numeric) ? value : "unknown"
  end

  def read_json(path)
    JSON.parse(File.read(path)) if File.file?(path)
  rescue JSON::ParserError
    nil
  end

  def git(repo, *args)
    output, error, status = Open3.capture3("git", "-C", repo, *args)
    raise "git #{args.first} failed: #{error}" unless status.success?

    output
  end

  def render(trials)
    lines = [
      "# Trial comparison report",
      "",
      "This is a diagnostic index of every recorded attempt. Fake-adapter rows are retained for auditability but excluded from research data. Counts describe changed files and text lines; they are not quality scores. No winner is selected and no statistical inference is made.",
      "The attempts table is not the assigned-cell denominator. Actual continuation turns under a cell are part of that existing cell; the final continuation code and agent time are included in the cell comparison. Separate `continuation_smoke` audit tasks are excluded.",
      "",
      "Token and cost values are reported only when present in aggregate usage events; a Codex field is summed only when every completed turn provides it. Missing values are `unknown`, never zero. Codex input tokens already include cached input; cache-read and cache-write counts are subsets, not additional input. Claude reports cache categories separately. Do not sum token categories across providers. Transcript contents and absolute workspace paths are not included.",
      "",
      "## Attempts",
      "",
      "| Trial path | Task | Agent | Model | Condition | Track | Status | Incident | Eligibility | Checks | Restored | Agent seconds | Input tokens | Output tokens | Cache read | Cache creation | Cost (USD) | Research data |",
      "|---|---|---|---|---|---|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|---|"
    ]

    trials.each do |trial|
      usage = trial.fetch(:usage)
      row = [
        link(trial[:path]), trial[:task], trial[:agent], trial[:model], trial[:condition], trial[:track],
        trial[:status], format_value(trial[:incident]), trial[:eligibility], trial[:checks], format_value(trial[:restoration]), format_value(trial[:seconds]),
        format_value(usage[:input_tokens]), format_value(usage[:output_tokens]),
        format_value(usage[:cache_read_input_tokens]), format_value(usage[:cache_creation_input_tokens]),
        format_value(usage[:cost_usd]),
        if trial[:eligibility] == "behavioral attempt"
          "included"
        elsif trial[:eligibility].start_with?("part of existing cell")
          "included via existing cell"
        else
          trial[:eligibility]
        end
      ]
      lines << "| #{row.map { |value| escape(value) }.join(' | ')} |"
    end

    lines.concat(["", "## Change counts", "", "Counts come from `git diff` between the saved baseline and final bundles. Binary file changes count as files, but not text lines.", ""])
    trials.each do |trial|
      lines << "### #{link(trial[:path])}"
      lines << ""
      lines << "| Area | Added files | Deleted files | Modified files | Added lines | Deleted lines |"
      lines << "|---|---:|---:|---:|---:|---:|"
      trial.fetch(:changes).each do |area, counts|
        lines << "| #{area} | #{counts[:added_files]} | #{counts[:deleted_files]} | #{counts[:modified_files]} | #{counts[:added_lines]} | #{counts[:deleted_lines]} |"
      end
      lines << "\nChange counts unavailable: #{trial[:change_error]}" if trial[:change_error]
      lines << ""
    end

    lines.join("\n") + "\n"
  end

  def link(path)
    "[#{path}](#{path})"
  end

  def format_value(value)
    value.nil? ? "unknown" : value.to_s
  end

  def escape(value)
    format_value(value).gsub("|", "\\|").gsub("\n", " ")
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 1
    abort "usage: ruby scripts/report.rb RESULTS_DIR"
  end

  begin
    print PilotReport.build(ARGV.fetch(0))
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
