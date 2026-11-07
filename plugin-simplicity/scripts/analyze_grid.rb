#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"
require_relative "grid_summary"
require_relative "report"
require_relative "session_metrics"

module GridAnalysisRenderer
  module_function

  STRUCTURAL_FIELDS = %w[method_definitions classes branch_nodes].freeze
  OUTPUT_FILES = %w[summary.json comparison.md code-index.md attempt-report.md session-metrics.json].freeze

  def render(grid_dir, output_dir)
    root = File.realpath(grid_dir)
    output = resolve_path(output_dir)
    raise "output directory must be outside the grid directory" if output == root || output.start_with?(root + File::SEPARATOR)

    summary = GridSummary.build(root)
    grid = JSON.parse(File.read(File.join(root, "grid.json")))
    runtime = runtime_summaries(summary.fetch("cells"))
    groups = add_recorded_wall_summaries(summary.fetch("groups"), summary.fetch("cells"))
    generated_at = Time.now.utc.iso8601
    document = summary.merge("generated_at" => generated_at, "groups" => groups, "cumulative_agent_execution_seconds" => runtime)
    FileUtils.mkdir_p(output)

    write(output, "summary.json", JSON.pretty_generate(document) + "\n")
    write(output, "comparison.md", comparison_markdown(groups, runtime, grid, summary.fetch("cells"), generated_at))
    write(output, "code-index.md", code_index(root, output, summary.fetch("cells")))
    write(output, "attempt-report.md", attempt_report(root, output))
    write(output, "session-metrics.json", JSON.pretty_generate(session_metrics(root, summary.fetch("cells"))) + "\n")
    OUTPUT_FILES.map { |name| File.join(output, name) }
  end

  def runtime_summaries(cells)
    complete = cells.select { |cell| cell["disposition"] == "complete" }.filter_map do |cell|
      value = cell["all_agent_execution_seconds"]
      value if value.is_a?(Numeric)
    end
    known = cells.filter_map do |cell|
      value = cell["known_agent_execution_seconds_sum"]
      value if value.is_a?(Numeric)
    end
    {
      "completed_cells" => numeric_summary(complete, cells.count { |cell| cell["disposition"] == "complete" } - complete.length),
      "all_outcomes_known_agent_time" => numeric_summary(known, cells.length - known.length),
      "definition" => "Sum of recorded agent execution seconds across the single recorded attempt/continuation chain per assigned cell; excludes verification-attempt backups. These are agent execution durations, not wall-clock time."
    }
  end

  def numeric_summary(values, unknown_count)
    values = values.sort
    median = if values.empty?
               "unknown"
             elsif values.length.odd?
               values[values.length / 2]
             else
               (values[values.length / 2 - 1] + values[values.length / 2]) / 2.0
             end
    {"n_known" => values.length, "n_unknown" => unknown_count, "median" => median,
     "range" => values.empty? ? "unknown" : {"min" => values.first, "max" => values.last}}
  end

  def add_recorded_wall_summaries(groups, cells)
    groups.map do |group|
      members = cells.select do |cell|
        cell.fetch("cell").values_at("agent", "task", "track", "condition") == group.values_at("agent", "task", "track", "condition")
      end
      correct_completed = members.select { |cell| cell["correctness"] == true && cell["disposition"] == "complete" }
      values = correct_completed.filter_map do |cell|
        value = cell["recorded_wall_seconds"]
        value if value.is_a?(Numeric)
      end
      group.merge("recorded_wall_seconds" => numeric_summary(values, correct_completed.length - values.length))
    end
  end

  def comparison_markdown(groups, runtime, grid, cells, generated_at)
    dispositions = GridSummary.disposition_counts(cells).select { |_status, count| count.positive? }
    pending = %w[running unstarted awaiting_review].sum { |status| dispositions.fetch(status, 0) }
    run_state = pending.positive? ? "In progress" : "All assigned cells have a recorded terminal disposition"
    repeats = grid.dig("options", "repeats")
    repeats = grid.fetch("cells").map { |cell| cell["repeat"] }.uniq.length unless repeats.is_a?(Numeric)
    status_summary = dispositions.map { |status, count| "#{status}=#{count}" }.join(", ")
    lines = [
      "# Assigned-cell comparison",
      "",
      "As of #{generated_at} (UTC): **#{run_state}**. Assigned cells: #{cells.length}; dispositions: #{status_summary}.",
      "",
      "Descriptive counts only; they are not quality grades or simplicity scores. Correctness is based on the recorded checker/restoration result. Review grading is pending. This grid contains #{grid.fetch("cells").length} assigned cells across #{grid.fetch("cells").map { |cell| cell["task"] }.uniq.length} tasks and #{repeats} assigned repeats per condition; these small samples do not establish a winner.",
      "",
      "Infrastructure/checker workflow changed after five assignments. The initial Codex kernel crash happened during smoke validation, outside this 48-cell grid; its incident record is excluded from these pilot cells. Read run incident notes before combining cells across the workflow transition.",
      "",
      "## Grouped cells",
      "",
      "| Agent | Task | Track | Condition | Correct / assigned | Completed | Status counts | Median production changed lines (correct only) | Median method delta | Median class delta | Median branch delta | Median recorded wall seconds (correct/complete) | Median cumulative agent seconds (completed) | Median known cumulative seconds (all outcomes) |",
      "|---|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|"
    ]

    groups.each do |group|
      dispositions = group.fetch("disposition_counts").select { |_key, count| count.positive? }.map { |key, count| "#{key}=#{count}" }.join(", ")
      seconds_group = cells.select { |cell| cell.fetch("cell").values_at("agent", "task", "track", "condition") == group.values_at("agent", "task", "track", "condition") }
      completed_times = seconds_group.select { |cell| cell["disposition"] == "complete" }.filter_map { |cell| cell["all_agent_execution_seconds"] if cell["all_agent_execution_seconds"].is_a?(Numeric) }
      all_times = seconds_group.filter_map { |cell| cell["known_agent_execution_seconds_sum"] if cell["known_agent_execution_seconds_sum"].is_a?(Numeric) }
      row = [
        group["agent"], group["task"], group["track"], group["condition"],
        "#{group["correct_solutions"]} / #{group["assigned_cells"]}", group.dig("disposition_counts", "complete").to_s,
        dispositions.empty? ? "none recorded" : dispositions,
        summary_median(group["production_changed_lines"]),
        *STRUCTURAL_FIELDS.map { |field| summary_median(group.dig("structural_deltas", field)) },
        summary_median(group["recorded_wall_seconds"]),
        numeric_summary(completed_times, group.dig("disposition_counts", "complete").to_i - completed_times.length).fetch("median").to_s,
        numeric_summary(all_times, group["assigned_cells"] - all_times.length).fetch("median").to_s
      ]
      lines << "| #{row.map { |value| escape(value) }.join(" | ")} |"
    end

    lines.concat([
      "",
      "`Correct / assigned` retains the assigned denominator. Production changed lines and structural medians use only checker-passing, restoration-verified solutions. Structural deltas are method definitions, classes, and branch nodes, respectively. Unknown measurements remain unknown.",
      "",
      "Recorded wall time is reported only for correct, completed cells when available. It spans the first recorded attempt start through the final attempt finish, so it includes elapsed gaps and evaluator/checker waiting; this pilot cannot attribute that time to the plugin or agent. Missing wall-time records remain unknown.",
      "",
      "## Cumulative execution-time medians",
      "",
      "Completed-only median: #{runtime.dig("completed_cells", "median")} seconds (n=#{runtime.dig("completed_cells", "n_known")}, unknown=#{runtime.dig("completed_cells", "n_unknown")}). All-outcome median over cells with any recorded agent duration: #{runtime.dig("all_outcomes_known_agent_time", "median")} seconds (n=#{runtime.dig("all_outcomes_known_agent_time", "n_known")}, unknown=#{runtime.dig("all_outcomes_known_agent_time", "n_unknown")}). The second population includes known partial chains for failures and unfinished cells.",
      "",
      "Agent execution durations above exclude checker runtime, waiting, human review, and unrecorded work. No review grade or quality winner is inferred."
    ])
    lines.join("\n") + "\n"
  end

  def summary_median(summary)
    return "unknown" unless summary.is_a?(Hash) && summary["median"].is_a?(Numeric)

    summary["median"].to_s
  end

  def code_index(root, output, cells)
    lines = [
      "# Assigned-cell code and artifact index",
      "",
      "One row per assigned cell, including unstarted cells. Recorded continuations count persisted continuation records; they do not establish that an evaluator responded or identify a person. Links are relative to this report directory. The index links to code/artifact files only; it does not embed prompts, transcript bodies, or credential metadata.",
      "",
      "| # | Agent | Task | Track | Condition | Disposition | Recorded continuations | Root attempt | Final workspace | Patch | Baseline bundle | Final bundle | Final worktree archives |",
      "|---:|---|---|---|---|---:|---|---|---|---|---|---|---|"
    ]
    cells.each do |cell|
      cell_dir = File.join(root, format("%04d", cell.fetch("grid_index")))
      nodes, = GridSummary.read_chain(cell_dir)
      initial_node = nodes.first
      final_node = nodes.last
      final_path = cell["final_path"] && File.join(root, cell["final_path"])
      first_path = initial_node&.fetch(:path, nil) || (File.directory?(cell_dir) ? File.realpath(cell_dir) : nil)
      final_dir = final_path || first_path
      root_link = path_link(output, first_path)
      workspace_link = path_link(output, bounded_workspace_path(root, final_node, initial_node))
      patch_link = path_link(output, final_dir && File.join(final_dir, "change.patch"))
      baseline_link = path_link(output, first_path && File.join(first_path, "baseline.bundle"))
      final_bundle_link = path_link(output, final_dir && File.join(final_dir, "final.bundle"))
      archive_links = worktree_archive_links(root, output, final_node)
      identity = cell.fetch("cell")
      values = [cell["grid_index"], identity["agent"], identity["task"], identity["track"], identity["condition"], cell["disposition"], cell["continuation_count"], root_link, workspace_link, patch_link, baseline_link, final_bundle_link, archive_links]
      lines << "| #{values.map { |value| value.is_a?(String) ? value : escape(value) }.join(" | ")} |"
    end
    lines.join("\n") + "\n"
  end

  def attempt_report(root, output)
    report = PilotReport.build(root)
    report.gsub(/\]\(([^)]+)\)/) do
      target = Regexp.last_match(1)
      absolute = File.expand_path(target, root)
      relative = Pathname.new(absolute).relative_path_from(Pathname.new(output)).to_s
      "](#{relative})"
    end
  end

  def session_metrics(root, cells)
    records = []
    cells.each do |cell|
      cell_dir = File.join(root, format("%04d", cell.fetch("grid_index")))
      nodes, = GridSummary.read_chain(cell_dir)
      nodes.each do |node|
        transcript = File.join(node.fetch(:path), "transcript.txt")
        meta = node.fetch(:meta)
        agent = meta["agent"]
        next unless %w[claude codex].include?(agent)

        metrics = SessionMetrics.parse(transcript, agent: agent)
        records << {
          "grid_index" => cell["grid_index"],
          "cell" => cell["cell"],
          "attempt" => Pathname.new(node.fetch(:path)).relative_path_from(Pathname.new(root)).to_s,
          "status" => meta["status"],
          "metrics" => metrics
        }
      end
    end
    {"scope" => "One record per actual attempt transcript in the recorded continuation chain. Verification-attempt backups are excluded; no transcript text is included.", "assigned_cells" => cells.length, "turn_records" => records}
  end

  def path_link(output, target)
    return "—" unless target && File.exist?(target)

    relative = Pathname.new(File.expand_path(target)).relative_path_from(Pathname.new(output)).to_s
    label = Pathname.new(target).relative_path_from(Pathname.new(File.dirname(target))).to_s
    "[#{escape(label)}](#{relative})"
  rescue ArgumentError
    "—"
  end

  def bounded_workspace_path(root, final_node, initial_node)
    final_candidate = final_node && final_node[:meta]["workspace_path"]
    resolved = bounded_existing_path(root, final_candidate)
    return resolved if resolved

    initial_workspace = initial_node && File.join(initial_node[:path], "workspace")
    bounded_existing_path(root, initial_workspace)
  end

  def worktree_archive_links(root, output, final_node)
    return "—" unless final_node

    links = Array(final_node[:meta]["worktrees"]).filter_map do |worktree|
      next unless worktree.is_a?(Hash) && worktree["archive"].is_a?(String)

      archive = bounded_existing_path(root, File.join(final_node[:path], worktree["archive"]))
      path_link(output, archive) if archive
    end
    links.empty? ? "—" : links.join(", ")
  end

  def bounded_existing_path(root, path)
    return unless path.is_a?(String) && !path.empty?

    candidate = File.expand_path(path, root)
    return unless candidate == root || candidate.start_with?(root + File::SEPARATOR)
    return unless File.exist?(candidate)

    resolved = File.realpath(candidate)
    resolved == root || resolved.start_with?(root + File::SEPARATOR) ? resolved : nil
  rescue Errno::ENOENT
    nil
  end

  def resolve_path(path)
    absolute = File.expand_path(path)
    suffix = []
    cursor = absolute
    until File.exist?(cursor)
      suffix.unshift(File.basename(cursor))
      parent = File.dirname(cursor)
      raise "cannot resolve output path" if parent == cursor
      cursor = parent
    end
    File.join(File.realpath(cursor), *suffix)
  end

  def write(output, name, contents)
    File.write(File.join(output, name), contents)
  end

  def escape(value)
    value.to_s.gsub("|", "\\|").gsub("\n", " ")
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/analyze_grid.rb GRID_DIR --output DIR"
    opts.on("--output DIR", "Write derived reports to DIR (outside GRID_DIR)") { |value| options[:output] = value }
  end
  begin
    parser.parse!
    abort(parser.to_s) unless ARGV.length == 1 && options[:output]
    GridAnalysisRenderer.render(ARGV.fetch(0), options.fetch(:output))
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
