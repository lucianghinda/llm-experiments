# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "minitest/mock"
require "open3"
require "tmpdir"
require_relative "../scripts/grid_summary"

class GridSummaryTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("grid-summary-test")
    @repo_root = Dir.mktmpdir("grid-summary-repos")
    @cells = [
      cell("claude", "report", "specified", "ruby-plainspoken", 1),
      cell("claude", "report", "specified", "ruby-plainspoken", 2),
      cell("codex", "report", "natural", "baseline", 1),
      cell("codex", "report", "natural", "baseline", 2),
      cell("claude", "report", "natural", "baseline", 1),
      cell("claude", "report", "natural", "baseline", 2),
      cell("codex", "report", "specified", "baseline", 1),
      cell("codex", "report", "specified", "baseline", 2),
      cell("codex", "csv_import", "natural", "baseline", 1),
      cell("claude", "identifiers", "natural", "baseline", 1)
    ]
    options = {"claude_model" => "claude-model", "codex_model" => "codex-model"}
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => options, "cells" => @cells))
  end

  def teardown
    FileUtils.remove_entry(@root)
    FileUtils.remove_entry(@repo_root)
  end

  def test_counts_all_assigned_cells_and_resolves_continuation_once
    first = write_trial(1, @cells[0], seconds: 3)
    set_times(first, "2026-11-02T00:00:00Z", "2026-11-02T00:01:00Z")
    verification = File.join(first, "verification-attempts", "original")
    FileUtils.mkdir_p(verification)
    File.write(File.join(verification, "meta.json"), JSON.generate("status" => "agent_failure", "condition" => "audit-copy"))
    recheck_success = File.join(first, "verification-attempts", "recheck-1")
    recheck_failure = File.join(first, "verification-attempts", "recheck-2")
    FileUtils.mkdir_p(recheck_success)
    FileUtils.mkdir_p(recheck_failure)
    File.write(File.join(recheck_success, "audit.json"), JSON.generate("passed" => true))
    File.write(File.join(recheck_failure, "audit.json"), JSON.generate("passed" => false))
    first_meta = JSON.parse(File.read(File.join(first, "meta.json")))
    first_meta["recheck_attempt"] = "verification-attempts/recheck-1"
    File.write(File.join(first, "meta.json"), JSON.generate(first_meta))
    parent = write_trial(2, @cells[1], status: "awaiting_review", checks_passed: false, seconds: 4)
    set_times(parent, "2026-11-02T00:05:00Z", "2026-11-02T00:06:00Z")
    child = write_trial(2, @cells[1], relative: "0002/continuations/answer-01", source_trial: parent, status: "awaiting_review", checks_passed: false, seconds: 5)
    set_times(child, "2026-11-02T00:07:00Z", "2026-11-02T00:08:00Z")
    final_turn = write_trial(2, @cells[1], relative: "0002/continuations/answer-02", source_trial: child, seconds: 6)
    set_times(final_turn, "2026-11-02T00:09:00Z", "2026-11-02T00:20:00Z")
    write_trial(3, @cells[2], status: "complete", checks_passed: false, seconds: 2)
    write_trial(4, @cells[3], status: "agent_failure", checks_passed: false, seconds: 1)
    infra = write_trial(5, @cells[4], status: "agent_failure", checks_passed: false)
    File.write(File.join(infra, "incident.json"), JSON.generate("eligible_behavioral_trial" => false, "classification" => "infrastructure_failure"))
    write_trial(6, @cells[5], status: "timeout", checks_passed: false, seconds: 12, timed_out: true)
    write_trial(7, @cells[6], status: "awaiting_review", checks_passed: false)
    FileUtils.mkdir_p(File.join(@root, "0008"))
    reviewed = write_trial(10, @cells[9], status: "awaiting_review", checks_passed: false)
    write_task_failure_disposition(reviewed)

    summary = JSON.parse(JSON.generate(GridSummary.build(@root)))

    assert_equal 10, summary.fetch("assigned_cells")
    assert_equal 1, summary.fetch("cells").first.fetch("attempt_count")
    assert_equal 2, summary.dig("disposition_counts", "complete")
    assert_equal 2, summary.dig("disposition_counts", "task_failure")
    assert_equal 1, summary.dig("disposition_counts", "agent_failure")
    assert_equal 1, summary.dig("disposition_counts", "infrastructure_failure")
    assert_equal 1, summary.dig("disposition_counts", "timeout")
    assert_equal 1, summary.dig("disposition_counts", "awaiting_review")
    assert_equal 1, summary.dig("disposition_counts", "running")
    assert_equal 1, summary.dig("disposition_counts", "unstarted")

    continued = summary.fetch("cells")[1]
    assert_equal "complete", continued.fetch("disposition")
    assert_equal true, continued.fetch("correctness")
    assert_equal 2, continued.fetch("continuation_count")
    assert_equal 4, continued.fetch("first_agent_execution_seconds")
    assert_equal 15, continued.fetch("all_agent_execution_seconds")
    assert_equal 900.0, continued.fetch("recorded_wall_seconds")
    assert_equal "0002/continuations/answer-02", continued.fetch("final_path")
    assert_equal true, continued.dig("retention", "core_artifacts_retained")
    assert_equal "verification-attempts/recheck-1", summary.fetch("cells").first.fetch("recheck_attempt_path")
    assert_equal({"attempts" => 2, "passed" => 1, "failed" => 1, "unknown" => 0}, summary.fetch("cells").first.fetch("recheck_audits"))
    assert_equal 1, summary.fetch("cells").first.fetch("checker_infrastructure_recovery_count")

    group = summary.fetch("groups").find do |row|
      row.values_at("agent", "task", "track", "condition") == ["claude", "report", "specified", "ruby-plainspoken"]
    end
    assert_equal 2, group.fetch("assigned_cells")
    assert_equal 2, group.fetch("correct_solutions")
    assert_equal 2, group.dig("production_changed_lines", "n_known")
    assert_equal 2, group.dig("production_changed_lines", "median")
    assert_equal({"min" => 2, "max" => 2}, group.dig("production_changed_lines", "range"))
    assert_equal 2, group.dig("recorded_wall_seconds", "n_known")
    assert_equal 480.0, group.dig("recorded_wall_seconds", "median")
    assert_equal({"min" => 60.0, "max" => 900.0}, group.dig("recorded_wall_seconds", "range"))
    assert_equal 2, group.dig("structural_deltas", "method_definitions", "n_known")
    assert_match(/Descriptive pilot evidence only/, summary.fetch("analysis_note"))
    refute_nil first
    refute_nil child
    refute_nil final_turn
  end

  def test_missing_metrics_remain_unknown_not_zero
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {}, "cells" => [cell("claude", "report", "natural", "baseline", 1)]))

    summary = GridSummary.build(@root)

    assert_equal 1, summary.dig("groups", 0, "assigned_cells")
    assert_equal 0, summary.dig("groups", 0, "correct_solutions")
    assert_equal "unknown", summary.dig("groups", 0, "production_changed_lines", "median")
    assert_equal 0, summary.dig("groups", 0, "production_changed_lines", "n_unknown")
    assert_equal "unknown", summary.dig("cells", 0, "first_agent_execution_seconds")
    assert_equal "unknown", summary.dig("cells", 0, "all_agent_execution_seconds")
  end

  def test_duplicate_cell_identities_are_reported_as_mismatches
    duplicate = @cells.first.dup
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {}, "cells" => [@cells.first, duplicate]))
    write_trial(1, @cells.first)
    write_trial(2, duplicate)

    summary = GridSummary.build(@root)

    assert_equal 2, summary.dig("disposition_counts", "identity_mismatch")
    assert_equal 2, summary.fetch("cells").count { |item| !item.fetch("identity_errors").empty? }
    assert_equal 0, summary.dig("groups", 0, "correct_solutions")
  end

  def test_multiple_continuations_remain_unresolved_without_scoring_the_parent
    cell_value = @cells.first
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {"claude_model" => "claude-model"}, "cells" => [cell_value]))
    parent = write_trial(1, cell_value, status: "awaiting_review", checks_passed: true)
    write_trial(1, cell_value, relative: "0001/continuations/answer-a", source_trial: parent)
    write_trial(1, cell_value, relative: "0001/continuations/answer-b", source_trial: parent)

    record = GridSummary.build(@root).fetch("cells").first

    assert_equal "awaiting_review", record.fetch("disposition")
    assert_equal "unknown", record.fetch("correctness")
    assert_equal "unknown", record.fetch("continuation_count")
    assert_match(/multiple continuations/, record.fetch("note"))
  end

  def test_continuation_cycle_remains_unresolved_without_scoring_the_parent
    cell_value = @cells.first
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {"claude_model" => "claude-model"}, "cells" => [cell_value]))
    write_trial(1, cell_value, status: "awaiting_review", checks_passed: true)

    summary = GridSummary.stub(:matching_children, ->(_root, current) { [current] }) do
      GridSummary.build(@root)
    end
    record = summary.fetch("cells").first

    assert_equal "awaiting_review", record.fetch("disposition")
    assert_equal "unknown", record.fetch("correctness")
    assert_match(/continuation cycle/, record.fetch("note"))
  end

  def test_malformed_meta_is_classified_as_infrastructure_failure
    cell_value = @cells.first
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {}, "cells" => [cell_value]))
    path = File.join(@root, "0001")
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "meta.json"), "[]")

    record = GridSummary.build(@root).fetch("cells").first

    assert_equal "infrastructure_failure", record.fetch("disposition")
    assert_equal "unknown", record.fetch("recorded_status")
    assert_match(/invalid metadata/, record.fetch("note"))
  end

  def test_missing_and_invalid_recorded_wall_timestamps_are_unknown
    cell_value = @cells.first
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {"claude_model" => "claude-model"}, "cells" => [cell_value]))
    path = write_trial(1, cell_value)

    record = GridSummary.build(@root).fetch("cells").first
    assert_equal "unknown", record.fetch("recorded_wall_seconds")
    stats = GridSummary.build(@root).dig("groups", 0, "recorded_wall_seconds")
    assert_equal 0, stats.fetch("n_known")
    assert_equal 1, stats.fetch("n_unknown")
    assert_equal "unknown", stats.fetch("median")

    set_times(path, "2026-11-02T00:02:00Z", "2026-11-02T00:01:00Z")
    assert_equal "unknown", GridSummary.build(@root).dig("cells", 0, "recorded_wall_seconds")
    set_times(path, "not-a-timestamp", "2026-11-02T00:01:00Z")
    assert_equal "unknown", GridSummary.build(@root).dig("cells", 0, "recorded_wall_seconds")
  end

  def test_awaiting_review_failure_needs_hash_bound_no_question_disposition
    cell_value = @cells.first
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {"claude_model" => "claude-model"}, "cells" => [cell_value]))
    path = write_trial(1, cell_value, status: "awaiting_review", checks_passed: false)

    record = GridSummary.build(@root).fetch("cells").first
    assert_equal "awaiting_review", record.fetch("disposition")
    assert_equal "unknown", record.fetch("correctness")

    disposition_path = write_task_failure_disposition(path)
    record = GridSummary.build(@root).fetch("cells").first
    assert_equal "task_failure", record.fetch("disposition")
    assert_equal false, record.fetch("correctness")

    meta_path = File.join(path, "meta.json")
    meta = JSON.parse(File.read(meta_path)).merge("error" => "post-review metadata change")
    File.write(meta_path, JSON.generate(meta))
    refute_equal Digest::SHA256.file(meta_path).hexdigest, JSON.parse(File.read(disposition_path))["meta_sha256"]
    record = GridSummary.build(@root).fetch("cells").first
    assert_equal "awaiting_review", record.fetch("disposition")
    assert_equal "unknown", record.fetch("correctness")
  end

  def test_checker_timeout_alone_does_not_become_subject_timeout_or_task_failure
    cell_value = @cells.first
    File.write(File.join(@root, "grid.json"), JSON.generate("options" => {"claude_model" => "claude-model"}, "cells" => [cell_value]))
    path = write_trial(1, cell_value, status: "awaiting_review", checks_passed: false)
    File.write(File.join(path, "checks.json"), JSON.generate([{"exit" => 1, "timed_out" => true}]))

    record = GridSummary.build(@root).fetch("cells").first

    assert_equal "awaiting_review", record.fetch("disposition")
    assert_equal "unknown", record.fetch("correctness")
  end

  private

  def cell(agent, task, track, condition, repeat)
    {"agent" => agent, "task" => task, "track" => track, "condition" => condition, "repeat" => repeat}
  end

  def write_trial(index, identity, relative: format("%04d", index), source_trial: nil, status: "complete", checks_passed: true, seconds: nil, timed_out: false)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(path)
    meta = identity.merge("status" => status, "model" => "#{identity.fetch("agent")}-model", "adapter" => "container", "checks_passed" => checks_passed, "restoration_verified" => status == "complete")
    meta["agent_run"] = {"seconds" => seconds, "timed_out" => timed_out} unless seconds.nil? && !timed_out
    meta["container"] = "retained-container"
    meta["source_trial"] = source_trial if source_trial
    File.write(File.join(path, "meta.json"), JSON.generate(meta))
    exit_code = checks_passed ? 0 : 1
    File.write(File.join(path, "checks.json"), JSON.generate([{"exit" => exit_code, "timed_out" => timed_out}]))
    File.write(File.join(path, "transcript.txt"), "transcript\n")
    File.write(File.join(path, "change.patch"), "diff\n")
    if source_trial
      repo = @repos.fetch(source_trial)
    else
      repo = new_repo
    end
    @repos ||= {}
    @repos[path] = repo
    baseline, final = revisions_and_bundles(path, repo)
    File.write(File.join(path, "snapshot.json"), JSON.generate("baseline" => baseline, "final" => final))
    path
  end

  def write_task_failure_disposition(path)
    meta_path = File.join(path, "meta.json")
    record = {
      "category" => "task_failure",
      "meta_sha256" => Digest::SHA256.file(meta_path).hexdigest,
      "reason" => "Reviewed acceptance failure with no pending question",
      "no_pending_question" => true
    }
    disposition_path = File.join(path, "disposition.json")
    File.write(disposition_path, JSON.generate(record))
    disposition_path
  end

  def set_times(path, started_at, finished_at)
    meta_path = File.join(path, "meta.json")
    meta = JSON.parse(File.read(meta_path)).merge("started_at" => started_at, "finished_at" => finished_at)
    File.write(meta_path, JSON.generate(meta))
  end

  def new_repo
    @repo_number = (@repo_number || 0) + 1
    repo = File.join(@repo_root, "repo-#{@repo_number}")
    FileUtils.mkdir_p(repo)
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "Grid Test")
    git(repo, "config", "user.email", "grid@example.invalid")
    File.write(File.join(repo, "app.rb"), "class App\n  def call = :old\nend\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "baseline")
    repo
  end

  def revisions_and_bundles(path, repo)
    baseline = git(repo, "rev-parse", "HEAD").strip
    git(repo, "update-ref", "refs/pilot/baseline", baseline)
    git(repo, "bundle", "create", File.join(path, "baseline.bundle"), "refs/pilot/baseline")
    @version_number = (@version_number || 0) + 1
    File.write(File.join(repo, "app.rb"), "class App\n  def call = :changed_#{@version_number}\nend\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "final")
    final = git(repo, "rev-parse", "HEAD").strip
    git(repo, "update-ref", "refs/pilot/final", final)
    git(repo, "bundle", "create", File.join(path, "final.bundle"), "refs/pilot/final")
    [baseline, final]
  end

  def git(repo, *args)
    output, error, status = Open3.capture3("git", "-C", repo, *args)
    raise error unless status.success?

    output
  end
end
