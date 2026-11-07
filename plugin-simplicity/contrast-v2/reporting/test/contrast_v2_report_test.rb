# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

module GridSummary
  class << self
    attr_accessor :metric_calls
  end

  def self.build(root)
    JSON.parse(File.read(File.join(root, "summary.json")))
  end

  def self.read_chain(start_path)
    nodes = []
    current = start_path
    loop do
      meta = JSON.parse(File.read(File.join(current, "meta.json")))
      nodes << {path: current, meta: meta}
      break unless meta["status"] == "awaiting_review"
      children = Dir.glob(File.join(start_path, "continuations", "*", "meta.json")).filter_map do |path|
        child = JSON.parse(File.read(path))
        File.dirname(path) if child["source_trial"] == current
      end
      break unless children.one?
      current = children.first
    end
    [nodes, nil]
  end

  def self.grouped_summaries(records)
    records.group_by { |record| record.fetch("cell").values_at("agent", "task", "track", "condition") }.map do |(agent, task, track, condition), group|
      correct = group.select { |record| record["correctness"] == true }
      lines = correct.filter_map { |record| record.dig("solution_metrics", "production_changed_lines") if record["solution_metrics"].is_a?(Hash) }
      {"agent" => agent, "task" => task, "track" => track, "condition" => condition,
       "assigned_cells" => group.length, "correct_solutions" => correct.length,
       "production_changed_lines" => {"n_known" => lines.length, "n_unknown" => correct.length - lines.length,
                                      "median" => lines.empty? ? "unknown" : lines.first}}
    end
  end

  def self.solution_metrics(first, final)
    self.metric_calls ||= []
    metric_calls << {first: first, final: final}
    {"production_changed_lines" => 9, "structural_delta" => {"ruby_files" => 1}, "dependency_files_changed" => []}
  end
end

require_relative "../contrast_v2_report"

class ContrastV2ReportTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("contrast-v2-report-test")
    @s1 = File.join(@tmp, "stage1")
    @s2 = File.join(@tmp, "stage2")
    @out = File.join(@tmp, "out")
    @source_repo = File.join(@tmp, "source-repo")
    @grid_summary = File.join(@source_repo, "scripts", "grid_summary.rb")
    @frozen_inputs = File.join(@tmp, "contrast-v2-protocol", "inputs")
    FileUtils.mkdir_p([@s1, @s2, File.dirname(@grid_summary), @frozen_inputs])
    File.write(@grid_summary, "# test stub\n")
    write(File.join(@s1, "grid.json"), {"cells" => [cell(1)]})
    write(File.join(@s2, "grid.json"), {"cells" => [cell(1)]})
    @source = File.join(@s1, "0001")
    FileUtils.mkdir_p([@source, File.join(@s2, "0001")])
    write(File.join(@s1, "0001", "meta.json"), {"task" => "task_a", "agent" => "claude", "model" => "claude-requested", "agent_run" => {"actual_model" => "claude-reported"}})
    write(File.join(@s2, "0001", "meta.json"), {"stage1_source_trial" => @source, "agent" => "claude", "agent_run" => {"actual_model" => "claude-reported"}})
    write(File.join(@s2, "0001", "checks.json"), [{"argv" => ["ruby", "/checks/task_a_followup.rb"], "exit" => 0}])
    write_summary(@s1, [record(cell(1), "complete", true, "0001")])
    write_summary(@s2, [record(cell(1), "unstarted", "unknown", "0001")])
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_partial_run_retains_denominators_and_model_observations
    report = build(target: 2)
    assert_equal "in_progress", report.fetch("state")
    assert_equal 1, report.dig("stage1_correctness", "assigned_denominator")
    assert_equal 1, report.dig("stage2_cumulative_correctness", "assigned_denominator")
    assert_equal true, report.dig("stage2_cells", 0, "followup_correctness")
    assert_equal "unknown", report.dig("actual_model_observations", "codex")
    assert_equal ["claude-reported"], report.dig("actual_model_observations", "claude")
  end

  def test_blocked_sidecar_is_counted_as_assignment_and_final_gate_requires_it
    FileUtils.rm_f(File.join(@s2, "0001", "meta.json"))
    write(File.join(@s2, "stage2-blocked", "0001.json"), {"grid_index" => 1, "cell" => cell(1), "status" => "blocked", "stage1_source_trial" => @source, "reason" => "source unavailable"})
    report = build(target: 1)
    assert_equal 1, report.dig("stage2_blocked_sidecars", "count")
    assert_equal "blocked", report.dig("stage2_cells", 0, "disposition")
    assert_equal 1, report.dig("sidecar_accounting", "stage2_grid_dispositions", "blocked")
    assert_equal "complete_1_each_sidecars_accounted", report.fetch("state")
  end

  def test_explicit_failed_conditional_outcomes_remain_incorrect
    write(File.join(@s2, "0001", "checks.json"), [{"argv" => ["ruby", "/checks/task_a_followup.rb"], "exit" => 1}])
    write_summary(@s2, [record(cell(1), "task_failure", false, "0001")])
    report = build(target: 1)
    assert_equal 1, report.dig("followup_correctness_conditional_on_stage1_correct", "incorrect")
    assert_equal 0, report.dig("followup_correctness_conditional_on_stage1_correct", "unknown")
    assert_equal 1, report.dig("stage2_cumulative_correctness_conditional_on_stage1_correct", "incorrect")
    assert_equal 0, report.dig("stage2_cumulative_correctness_conditional_on_stage1_correct", "unknown")
  end

  def test_followup_check_and_actual_model_use_final_continuation
    initial = File.join(@s2, "0001")
    continuation = File.join(initial, "continuations", "final")
    FileUtils.mkdir_p(continuation)
    write(File.join(initial, "meta.json"), {"status" => "awaiting_review", "agent" => "claude", "stage1_source_trial" => @source})
    write(File.join(continuation, "meta.json"), {"status" => "complete", "agent" => "claude", "actual_model" => "claude-final-model", "source_trial" => initial})
    write(File.join(continuation, "checks.json"), [{"argv" => ["ruby", "/checks/task_a_followup.rb"], "exit" => 1}])
    write_summary(@s2, [record(cell(1), "task_failure", false, "0001/continuations/final")])
    report = build(target: 1)
    assert_equal false, report.dig("stage2_cells", 0, "followup_correctness")
    assert_equal ["claude-final-model", "claude-reported"].sort, report.dig("actual_model_observations", "claude").sort
  end

  def test_completed_cell_makes_old_blocked_sidecar_historical
    write(File.join(@s2, "stage2-blocked", "0001.json"), {"grid_index" => 1, "cell" => cell(1), "status" => "blocked", "reason" => "stale planner record"})
    write_summary(@s2, [record(cell(1), "complete", true, "0001")])
    report = build(target: 1)
    assert_equal 0, report.dig("stage2_blocked_sidecars", "count")
    assert_equal 1, report.dig("stage2_historical_blocked_sidecars", "count")
    assert_equal "complete", report.dig("stage2_cells", 0, "disposition")
  end

  def test_assignment_identity_or_source_mismatch_keeps_run_in_progress
    write(File.join(@s2, "grid.json"), {"cells" => [cell(2)]})
    stage2_record = record(cell(2), "unstarted", "unknown", "unknown")
    write_summary(@s2, [stage2_record])
    report = build(target: 1)
    assert_equal "in_progress", report.fetch("state")
    assert_includes report.dig("stage2_cells", 0, "join_errors"), "no matching stage-1 assignment"
  end

  def test_missing_stage2_grid_is_zero_current_assignments_against_planned_target
    FileUtils.rm_f(File.join(@s2, "grid.json"))
    report = build(target: 2)
    assert_equal 0, report.dig("assigned_cells", "stage2")
    assert_equal 2, report.dig("planned_cells", "stage2")
    assert_includes File.read(File.join(@out, "report.md")), "a missing grid is reported as 0 currently assigned, not as a completed empty stage"
    assert_equal "in_progress", report.fetch("state")
  end

  def test_final_gate_rejects_identity_errors_and_fake_dispositions
    bad_identity = record(cell(1), "complete", true, "0001").merge("identity_errors" => ["trial condition mismatch"])
    write_summary(@s1, [bad_identity])
    report = build_to(File.join(@tmp, "out-identity"), target: 1)
    assert_equal "in_progress", report.fetch("state")

    write_summary(@s1, [record(cell(1), "complete", true, "0001")])
    write_summary(@s2, [record(cell(1), "fake", "unknown", "0001")])
    report = build_to(File.join(@tmp, "out-fake"), target: 1)
    assert_equal "in_progress", report.fetch("state")
  end

  def test_operator_protocol_deviation_is_unknown_not_failure_and_blocks_paired_source
    write_summary(@s1, [record(cell(1), "task_failure", false, "0001")])
    sidecar_path = File.join(@s1, "0001", "protocol-deviation.json")
    write(sidecar_path, {"classification" => "operator_protocol_error", "eligible_behavioral_trial" => false,
                         "subject_response" => "wrong newline behavior", "fixed_contract_facts" => {"separator" => "; "}})

    report = build(target: 1)

    assert_equal 1, report.dig("assigned_cells", "stage1")
    assert_equal 1, report.dig("stage1_correctness", "assigned_denominator")
    assert_equal 1, report.dig("stage1_correctness", "unknown")
    assert_equal 0, report.dig("stage1_correctness", "incorrect")
    assert_equal 0, report.dig("stage1_behavioral_correctness", "assigned_denominator")
    assert_equal "task_failure", report.dig("stage1_cells", 0, "raw_disposition")
    assert_equal "operator_error", report.dig("stage1_cells", 0, "disposition")
    assert_equal "unknown", report.dig("stage1_cells", 0, "correctness")
    assert_equal "blocked", report.dig("stage2_cells", 0, "disposition")
    assert_equal true, report.dig("stage2_cells", 0, "invalid_source_blocked")
    assert_equal "complete_1_each_sidecars_accounted", report.fetch("state")
    assert_equal File.realpath(sidecar_path), report.dig("protocol_deviations", "entries", 0, "sidecar_path")
    markdown = File.read(File.join(@out, "report.md"))
    assert_includes markdown, "operator_protocol_error"
    assert_includes markdown, "protocol-deviation.json"
    assert_includes markdown, "not plugin/model failures"
    refute_includes markdown, "wrong newline behavior"
  end

  def test_stage1_source_provenance_mismatch_is_not_joined
    wrong_source = File.join(@tmp, "wrong-source")
    FileUtils.mkdir_p(wrong_source)
    write(File.join(@s2, "0001", "meta.json"), {"stage1_source_trial" => wrong_source, "agent" => "claude"})
    report = build(target: 1)
    assert_equal "in_progress", report.fetch("state")
    assert_includes report.dig("stage2_cells", 0, "join_errors"), "stage1_source_trial does not match joined stage-1 final path"
  end

  def test_stage2_metrics_are_explicitly_incremental
    write_summary(@s2, [record(cell(1), "complete", true, "0001")])
    report = build(target: 1)
    assert report.fetch("production_metrics").key?("stage2_incremental_patch_from_stage1_final")
    assert report.fetch("production_metrics").key?("stage2_final_vs_original_stage1_baseline")
    refute report.fetch("production_metrics").key?("stage2_whole_patch")
    assert_includes File.read(File.join(@out, "report.md")), "| Stage 2 incremental patch | claude | task_a | specified | condition_a | 1 | 4 |"
  end

  def test_original_baseline_metric_uses_stage1_root_and_stage2_final_even_when_stage1_failed
    write_summary(@s1, [record(cell(1), "task_failure", false, "0001")])
    write(File.join(@s1, "0001", "snapshot.json"), {"baseline" => "original-base", "final" => "stage1-final"})
    write(File.join(@s2, "0001", "snapshot.json"), {"baseline" => "stage1-final", "final" => "stage2-final"})
    write_summary(@s2, [record(cell(1), "complete", true, "0001")])

    report = build(target: 1)
    call = GridSummary.metric_calls.last

    assert_equal File.join(@s1, "0001"), call.dig(:first, :path)
    assert_equal "original-base", call.dig(:first, :snapshot, "baseline")
    assert_equal File.realpath(File.join(@s2, "0001")), call.dig(:final, :path)
    assert_equal "stage2-final", call.dig(:final, :snapshot, "final")
    assert_equal 9, report.dig("production_metrics", "stage2_final_vs_original_stage1_baseline", 0, "production_changed_lines", "median")
  end

  def test_output_cannot_be_written_inside_protected_roots_or_overwrite_primary_files
    assert_raises(RuntimeError) { build_to(File.join(@s1, "reports")) }
    assert_raises(RuntimeError) { build_to(File.join(@frozen_inputs, "report")) }
    assert_raises(RuntimeError) { build_to(File.join(@source_repo, "reports")) }
    FileUtils.mkdir_p(@out)
    File.write(File.join(@out, "summary.json"), "keep")
    assert_raises(RuntimeError) { build(target: 1) }
  end

  private

  def build(target:)
    build_to(@out, target: target)
  end

  def build_to(output, target: 1)
    ContrastV2Report.build(stage1_root: @s1, stage2_root: @s2, grid_summary_path: @grid_summary,
                           frozen_inputs: @frozen_inputs, output: output, target: target)
  end

  def cell(repeat)
    {"task" => "task_a", "agent" => "claude", "condition" => "condition_a", "track" => "specified", "repeat" => repeat}
  end

  def record(assignment, disposition, correctness, final_path)
    {"grid_index" => 1, "cell" => assignment, "disposition" => disposition, "correctness" => correctness,
     "final_path" => final_path, "first_agent_execution_seconds" => 10, "all_agent_execution_seconds" => 15,
     "recorded_wall_seconds" => 30, "solution_metrics" => {"production_changed_lines" => 4}}
  end

  def write_summary(root, cells)
    groups = [{"agent" => "claude", "task" => "task_a", "track" => "specified", "condition" => "condition_a",
               "assigned_cells" => cells.length, "correct_solutions" => cells.count { |record| record["correctness"] == true },
               "production_changed_lines" => {"n_known" => 1, "n_unknown" => 0, "median" => 4, "range" => {"min" => 4, "max" => 4}}}]
    write(File.join(root, "summary.json"), {"cells" => cells, "groups" => groups})
  end

  def write(path, object)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(object))
  end
end
