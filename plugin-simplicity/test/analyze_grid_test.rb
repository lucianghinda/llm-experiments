# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/analyze_grid"

class AnalyzeGridTest < Minitest::Test
  def test_renders_relative_reports_once_per_assigned_cell_and_turn_without_raw_overwrite
    Dir.mktmpdir("analysis-test") do |directory|
      grid = File.join(directory, "grid")
      output = File.join(directory, "derived")
      seed_grid(grid)
      before = File.binread(File.join(grid, "grid.json"))

      GridAnalysisRenderer.render(grid, output)

      assert_equal before, File.binread(File.join(grid, "grid.json"))
      GridAnalysisRenderer::OUTPUT_FILES.each { |name| assert File.file?(File.join(output, name)), name }
      summary = JSON.parse(File.read(File.join(output, "summary.json")))
      assert_equal 2, summary.fetch("assigned_cells")
      assert_equal 1, summary.fetch("groups").length
      wall = summary.dig("groups", 0, "recorded_wall_seconds")
      assert_equal 0, wall.fetch("n_known")
      assert_equal 1, wall.fetch("n_unknown")
      assert_equal "unknown", wall.fetch("median")
      assert_equal 1, summary.dig("cumulative_agent_execution_seconds", "completed_cells", "n_known")
      assert_equal 15, summary.dig("cumulative_agent_execution_seconds", "completed_cells", "median")

      index = File.read(File.join(output, "code-index.md"))
      assert_equal 2, index.lines.count { |line| line.match?(/^\| \d+ \|/) }
      assert_includes index, "(../grid/0001)"
      assert_includes index, "(../grid/0001/continuations/turn-2/final-workspace)"
      assert_includes index, "[worktree-1.tar.gz](../grid/0001/continuations/turn-2/worktree-1.tar.gz)"
      assert_includes index, "Recorded continuations"
      assert_includes index, "| 1 | claude | report | natural | baseline | complete | 1 |"
      assert_includes index, "| 2 | claude | report | natural | baseline | unstarted | 0 |"

      comparison = File.read(File.join(output, "comparison.md"))
      assert_includes comparison, "As of "
      assert_includes comparison, "In progress"
      assert_includes comparison, "complete=1, unstarted=1"
      assert_includes comparison, "1 / 2"
      assert_includes comparison, "2 assigned repeats per condition"
      assert_includes comparison, "Median recorded wall seconds (correct/complete)"
      assert_includes comparison, "evaluator/checker waiting"
      assert_includes comparison, "Completed-only median: 15 seconds"
      assert_includes comparison, "Review grading is pending"

      report = File.read(File.join(output, "attempt-report.md"))
      assert_includes report, "(../grid/0001)"
      refute_match(/\]\(0001\)/, report)

      sessions = JSON.parse(File.read(File.join(output, "session-metrics.json")))
      turns = sessions.fetch("turn_records")
      assert_equal 2, turns.length
      assert_equal ["0001", "0001/continuations/turn-2"], turns.map { |turn| turn.fetch("attempt") }
      assert turns.all? { |turn| turn.dig("metrics", "question_texts") == "omitted" }

      all_output = GridAnalysisRenderer::OUTPUT_FILES.map { |name| File.read(File.join(output, name)) }.join
      refute_includes all_output, "SENTINEL_PRIVATE_TRANSCRIPT_BODY"
      refute_includes all_output, directory
    end
  end

  def test_external_continuation_workspace_path_is_rejected_in_favor_of_initial_workspace
    Dir.mktmpdir("analysis-test") do |directory|
      grid = File.join(directory, "grid")
      output = File.join(directory, "derived")
      outside = File.join(directory, "outside-workspace")
      FileUtils.mkdir_p(outside)
      seed_grid(grid, continuation_workspace: outside)

      GridAnalysisRenderer.render(grid, output)

      index = File.read(File.join(output, "code-index.md"))
      assert_includes index, "[workspace](../grid/0001/workspace)"
      refute_includes index, "outside-workspace"
    end
  end

  def test_rejects_output_inside_raw_grid
    Dir.mktmpdir("analysis-test") do |directory|
      grid = File.join(directory, "grid")
      seed_grid(grid)
      error = assert_raises(RuntimeError) { GridAnalysisRenderer.render(grid, File.join(grid, "derived")) }
      assert_match(/outside the grid directory/, error.message)
      refute File.exist?(File.join(grid, "derived"))
    end
  end

  def test_recorded_wall_summary_uses_only_correct_completed_cells
    identity = {"agent" => "claude", "task" => "report", "track" => "natural", "condition" => "baseline"}
    group = identity.merge("assigned_cells" => 3)
    cells = [
      {"cell" => identity, "correctness" => true, "disposition" => "complete", "recorded_wall_seconds" => 25.0},
      {"cell" => identity, "correctness" => true, "disposition" => "complete"},
      {"cell" => identity, "correctness" => false, "disposition" => "task_failure", "recorded_wall_seconds" => 999.0}
    ]

    summary = GridAnalysisRenderer.add_recorded_wall_summaries([group], cells).fetch(0).fetch("recorded_wall_seconds")

    assert_equal 1, summary.fetch("n_known")
    assert_equal 1, summary.fetch("n_unknown")
    assert_equal 25.0, summary.fetch("median")
  end

  private

  def seed_grid(root, continuation_workspace: nil)
    cell = {"task" => "report", "agent" => "claude", "track" => "natural", "condition" => "baseline", "repeat" => 1}
    unstarted_cell = cell.merge("repeat" => 2)
    FileUtils.mkdir_p(File.join(root, "0001", "workspace"))
    final_workspace = File.join(File.realpath(root), "0001", "continuations", "turn-2", "final-workspace")
    FileUtils.mkdir_p(final_workspace)
    FileUtils.mkdir_p(File.join(root, "0001", "verification-attempts", "backup"))
    File.write(File.join(root, "grid.json"), JSON.generate("options" => {"claude_model" => "model-x", "repeats" => 2}, "cells" => [cell, unstarted_cell]))
    File.write(File.join(root, "0001", "baseline.bundle"), "placeholder bundle")
    File.write(File.join(root, "0001", "change.patch"), "first patch")
    File.write(File.join(root, "0001", "final.bundle"), "first final bundle")
    File.write(File.join(root, "0001", "workspace", "app.rb"), "# first workspace\n")
    File.write(File.join(root, "0001", "continuations", "turn-2", "change.patch"), "final patch")
    File.write(File.join(root, "0001", "continuations", "turn-2", "final.bundle"), "final bundle")
    File.write(File.join(final_workspace, "app.rb"), "# final workspace\n")
    File.write(File.join(root, "0001", "continuations", "turn-2", "worktree-1.tar.gz"), "worktree archive")
    root_path = File.realpath(File.join(root, "0001"))
    write_attempt(root_path, "awaiting_review", 10, false, source: nil)
    write_attempt(File.join(root_path, "continuations", "turn-2"), "complete", 5, true, source: root_path, workspace_path: continuation_workspace || final_workspace, worktrees: [{"archive" => "worktree-1.tar.gz"}])
    write_attempt(File.join(root_path, "verification-attempts", "backup"), "complete", 999, true, source: nil)
    File.write(File.join(root_path, "continuations", "turn-2", "snapshot.json"), JSON.generate("baseline" => "base", "final" => "final"))
  end

  def write_attempt(path, status, seconds, checks_passed, source:, workspace_path: nil, worktrees: nil)
    meta = {
      "task" => "report", "agent" => "claude", "track" => "natural", "condition" => "baseline",
      "model" => "model-x", "status" => status, "checks_passed" => checks_passed,
      "restoration_verified" => checks_passed,
      "source_trial" => source,
      "workspace_path" => workspace_path, "worktrees" => worktrees,
      "agent_run" => {"seconds" => seconds}
    }.compact
    File.write(File.join(path, "meta.json"), JSON.generate(meta))
    File.write(File.join(path, "checks.json"), JSON.generate([{"exit" => 0, "timed_out" => false}]))
    event = {"type" => "assistant", "message" => {"content" => [{"type" => "text", "text" => "SENTINEL_PRIVATE_TRANSCRIPT_BODY?"}]}}
    File.write(File.join(path, "transcript.txt"), JSON.generate(event) + "\n")
  end
end
