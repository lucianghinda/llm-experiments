# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../prepare_stage2"
require_relative "../prepare_stage2_grid"
require_relative "../support/harness"

class PrepareStage2Test < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("contrast-v2")
    @catalog = File.join(@tmp, "catalog")
    @fixture = File.join(@catalog, "fixtures", "demo")
    @trial = File.join(@tmp, "stage1")
    FileUtils.mkdir_p([File.join(@fixture, "test"), File.join(@catalog, "checks"), File.join(@catalog, "prompts")])
    File.write(File.join(@fixture, "app.rb"), "stage1 implementation\n")
    File.write(File.join(@fixture, "README.md"), "preserved code docs\n")
    File.write(File.join(@fixture, "test", "test_app.rb"), "puts 'original visible test'\n")
    File.write(File.join(@fixture, "test_support.rb"), "ORIGINAL_SUPPORT = true\n")
    File.write(File.join(@catalog, "prompts", "followup.txt"), "Please extend behavior.\n")
    File.write(File.join(@catalog, "prompts", "natural.txt"), "Natural initial prompt.\n")
    File.write(File.join(@catalog, "prompts", "specified.txt"), "Required API: preserve the existing header mapping.\n")
    File.write(File.join(@catalog, "checks", "initial.rb"), "exit 0\n")
    File.write(File.join(@catalog, "checks", "followup.rb"), "exit 0\n")
    File.write(File.join(@catalog, "tasks.json"), JSON.pretty_generate([
      {
        "id" => "demo", "fixture" => "fixtures/demo",
        "prompt" => {"natural" => "prompts/natural.txt", "specified" => "prompts/specified.txt"},
        "checks" => [["ruby", "test/test_app.rb"], ["ruby", "{root}/checks/initial.rb"]],
        "followup" => {"prompt" => "prompts/followup.txt", "checks" => [["ruby", "{root}/checks/followup.rb"]]}
      }
    ]))
    File.write(File.join(@catalog, "conditions.json"), JSON.pretty_generate([{"id" => "base", "plugin_path" => nil}, {"id" => "treatment", "plugin_path" => "/kept/as/assigned"}]))
    make_stage1_trial
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def make_stage1_trial
    FileUtils.mkdir_p(@trial)
    system("git", "init", "-q", @fixture, exception: true)
    system("git", "-C", @fixture, "config", "user.name", "Test", exception: true)
    system("git", "-C", @fixture, "config", "user.email", "test@example.invalid", exception: true)
    system("git", "-C", @fixture, "add", "-A", exception: true)
    system("git", "-C", @fixture, "commit", "-qm", "stage 1", exception: true)
    baseline = Pilot.git(@fixture, "rev-parse", "HEAD").strip
    File.write(File.join(@fixture, "app.rb"), "stage1 final implementation\n")
    FileUtils.mkdir_p(File.join(@fixture, "agent-notes"))
    File.write(File.join(@fixture, "agent-notes", "detail.md"), "subject-created content\n")
    Pilot.snapshot(@fixture, @trial, baseline)
    File.write(File.join(@trial, "checks.json"), JSON.pretty_generate([{"exit" => 0, "timed_out" => false}]))
    File.write(File.join(@trial, "meta.json"), JSON.pretty_generate(
      "status" => "complete", "workspace_stable" => true, "restoration_verified" => true,
      "checks_passed" => true, "task" => "demo", "agent" => "codex", "model" => "model",
      "track" => "specified", "condition" => "treatment", "repeat" => 2
    ))
  end

  def make_grid_for(trial, status: "complete", stable: true)
    grid = File.join(@tmp, "stage1-grid")
    cell = File.join(grid, "0001")
    FileUtils.mkdir_p(cell)
    FileUtils.cp_r(Dir.children(trial).map { |entry| File.join(trial, entry) }, cell)
    meta_path = File.join(cell, "meta.json")
    meta = JSON.parse(File.read(meta_path)).merge("status" => status, "workspace_stable" => stable)
    meta["session_id"] = "session-demo" if status == "awaiting_review"
    File.write(meta_path, JSON.pretty_generate(meta))
    File.write(File.join(grid, "grid.json"), JSON.pretty_generate(
      "options" => {"output" => grid, "codex_model" => "model", "claude_model" => "claude-model", "codex_auth_file" => "/auth/codex", "claude_auth_file" => "/auth/claude", "image" => "old-image"},
      "cells" => [{"task" => "demo", "agent" => "codex", "track" => "specified", "condition" => "treatment", "repeat" => 2}]
    ))
    grid
  end

  def test_prepares_clean_stage2_fixture_and_cumulative_checks
    out = File.join(@tmp, "prepared")
    manifest = ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: out, stage_kind: "task_extension")
    fixture = File.join(out, "fixtures", "demo")
    task = JSON.parse(File.read(File.join(out, "tasks.json"))).fetch(0)
    conditions = JSON.parse(File.read(File.join(out, "conditions.json")))

    assert_equal "stage1 final implementation\n", File.read(File.join(fixture, "app.rb"))
    assert_equal "preserved code docs\n", File.read(File.join(fixture, "README.md"))
    assert_equal "subject-created content\n", File.read(File.join(fixture, "agent-notes", "detail.md"))
    assert_equal "puts 'original visible test'\n", File.read(File.join(fixture, "test", "test_app.rb"))
    assert_equal "ORIGINAL_SUPPORT = true\n", File.read(File.join(fixture, "test_support.rb"))
    refute File.exist?(File.join(fixture, ".git"))
    assert_equal [["ruby", "test/test_app.rb"], ["ruby", "{root}/checks/initial.rb"], ["ruby", "{root}/checks/followup.rb"]], task.fetch("checks")
    assert_equal "prompts/demo/followup.txt", task.fetch("prompt").fetch("natural")
    assert_equal "Existing required behavior\nRequired API: preserve the existing header mapping.\n\nNew request\nPlease extend behavior.\n", File.read(File.join(out, "prompts/demo/followup.txt"))
    assert_equal "treatment", conditions.find { |condition| condition["id"] == "treatment" }.fetch("id")
    assert_equal File.realpath(@trial), manifest.fetch("stage1_source_trial")
    refute manifest.key?("source_trial")
    assert_equal "passed", manifest.fetch("stage1_outcome")
    assert_equal 900, manifest.fetch("stage_timeout_seconds")
    assert_equal "task_extension", manifest.fetch("stage_kind")
  end

  def test_extension_prompt_hashes_raw_followup_and_combines_specified_contract_for_both_tracks
    specified_out = File.join(@tmp, "specified-prepared")
    specified = ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: specified_out, stage_kind: "task_extension")
    natural_trial = File.join(@tmp, "natural-stage1")
    FileUtils.mkdir_p(natural_trial)
    FileUtils.cp_r(Dir.children(@trial).map { |entry| File.join(@trial, entry) }, natural_trial)
    natural_meta_path = File.join(natural_trial, "meta.json")
    natural_meta = JSON.parse(File.read(natural_meta_path)).merge("track" => "natural", "condition" => "base")
    File.write(natural_meta_path, JSON.pretty_generate(natural_meta))
    natural_out = File.join(@tmp, "natural-prepared")
    natural = ContrastV2.prepare(source_trial: natural_trial, catalog: @catalog, output: natural_out, stage_kind: "task_extension")

    expected_prompt = "Existing required behavior\nRequired API: preserve the existing header mapping.\n\nNew request\nPlease extend behavior.\n"
    prompt = File.read(File.join(specified_out, "prompts/demo/followup.txt"))
    assert_equal expected_prompt, prompt
    assert_equal Digest::SHA256.hexdigest("Please extend behavior.\n"), specified.fetch("followup_prompt_sha256")
    assert_equal Digest::SHA256.hexdigest("Required API: preserve the existing header mapping.\n"), specified.fetch("initial_contract_sha256")
    assert_equal Digest::SHA256.hexdigest(expected_prompt), specified.fetch("stage2_prompt_sha256")
    assert_equal "specified_initial_contract_plus_followup", specified.fetch("prompt_context")
    assert_equal prompt, File.read(File.join(natural_out, "prompts/demo/followup.txt"))
    assert_equal specified.fetch("stage2_prompt_sha256"), natural.fetch("stage2_prompt_sha256")
    assert_equal "natural", natural.fetch("track")
    assert_equal "base", natural.fetch("condition")
  end

  def test_clarification_prompt_keeps_followup_only_context
    out = File.join(@tmp, "clarification-prompt")
    manifest = ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: out, stage_kind: "clarification")
    assert_equal "Please extend behavior.\n", File.read(File.join(out, "prompts/demo/followup.txt"))
    assert_equal Digest::SHA256.hexdigest("Please extend behavior.\n"), manifest.fetch("stage2_prompt_sha256")
    assert_equal "followup_only", manifest.fetch("prompt_context")
  end

  def test_classifies_failed_stage1_and_rejects_unstable_source_without_output
    meta_path = File.join(@trial, "meta.json")
    meta = JSON.parse(File.read(meta_path))
    meta["checks_passed"] = false
    meta["status"] = "awaiting_review"
    File.write(meta_path, JSON.pretty_generate(meta))
    manifest = ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: File.join(@tmp, "failed-prepared"), stage_kind: "clarification")
    assert_equal "failed", manifest.fetch("stage1_outcome")

    meta["workspace_stable"] = false
    File.write(meta_path, JSON.pretty_generate(meta))
    out = File.join(@tmp, "rejected")
    error = assert_raises(RuntimeError) do
      ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: out, stage_kind: "clarification")
    end
    assert_includes error.message, "not stable"
    refute File.exist?(out)
  end

  def test_does_not_delete_preexisting_output_when_preparation_is_rejected
    out = File.join(@tmp, "protected-output")
    FileUtils.mkdir_p(out)
    sentinel = File.join(out, "keep.txt")
    File.write(sentinel, "existing data\n")
    error = assert_raises(RuntimeError) do
      ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: out, stage_kind: "clarification")
    end
    assert_includes error.message, "output already exists"
    assert_equal "existing data\n", File.read(sentinel)
  end

  def test_noncomplete_source_with_passing_checks_is_unknown
    meta_path = File.join(@trial, "meta.json")
    meta = JSON.parse(File.read(meta_path)).merge("status" => "infrastructure_failure", "checks_passed" => true)
    File.write(meta_path, JSON.pretty_generate(meta))
    manifest = ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: File.join(@tmp, "unknown-prepared"), stage_kind: "clarification")
    assert_equal "unknown", manifest.fetch("stage1_outcome")
  end

  def test_stage2_runner_records_provenance_without_continuation_link
    prepared = File.join(@tmp, "prepared")
    ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: prepared, stage_kind: "clarification")
    output = File.join(@tmp, "stage2-run")
    script = File.join(__dir__, "..", "run_stage2.rb")
    command = [RbConfig.ruby, script, "--prepared", prepared, "--task", "demo", "--agent", "codex", "--condition", "treatment", "--model", "model", "--track", "specified", "--output", output, "--fake-command", "/usr/bin/true"]
    stdout, stderr, status = Open3.capture3(*command)
    assert status.success?, "#{stderr}\n#{stdout}"
    meta = JSON.parse(File.read(File.join(output, "meta.json")))
    assert_equal 2, meta.fetch("stage")
    assert_equal "clarification", meta.fetch("stage_kind")
    assert_equal File.realpath(@trial), meta.fetch("stage1_source_trial")
    assert_equal "passed", meta.fetch("stage1_outcome")
    assert_equal "followup_only", meta.fetch("prompt_context")
    assert_equal Digest::SHA256.hexdigest("Please extend behavior.\n"), meta.fetch("followup_prompt_sha256")
    assert_equal Digest::SHA256.hexdigest("Please extend behavior.\n"), meta.fetch("stage2_prompt_sha256")
    refute meta.key?("source_trial"), "stage 2 must not be linked as a continuation"
  end

  def test_stage2_runner_rejects_a_different_budget
    prepared = File.join(@tmp, "prepared")
    ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: prepared, stage_kind: "clarification")
    output = File.join(@tmp, "wrong-budget")
    command = [RbConfig.ruby, File.join(__dir__, "..", "run_stage2.rb"), "--prepared", prepared,
               "--task", "demo", "--agent", "codex", "--condition", "treatment", "--model", "model",
               "--track", "specified", "--timeout", "899", "--output", output]
    _stdout, stderr, status = Open3.capture3(*command)
    refute status.success?
    assert_includes stderr, "stage-2 timeout must be 900 seconds"
    refute File.exist?(output)
  end

  def test_stage2_runner_rejects_assignment_overrides_and_duplicate_flags
    prepared = File.join(@tmp, "prepared")
    ContrastV2.prepare(source_trial: @trial, catalog: @catalog, output: prepared, stage_kind: "clarification")
    base = [RbConfig.ruby, File.join(__dir__, "..", "run_stage2.rb"), "--prepared", prepared,
            "--task", "demo", "--agent", "codex", "--condition", "treatment", "--model", "model",
            "--track", "specified", "--output", File.join(@tmp, "never-run")]
    [["--condition=base"], ["--condition", "treatment"], ["--catalog", @catalog]].each do |override|
      _stdout, stderr, status = Open3.capture3(*(base + override))
      refute status.success?
      assert_match(/differs from prepared assignment|exactly once|catalog is fixed/, stderr)
    end
  end

  def test_grid_driver_prepares_assignments_from_grid_summary_and_emits_next_command
    source_grid = make_grid_for(@trial)
    output = File.join(@tmp, "stage2-grid")
    prepared = File.join(@tmp, "prepared-catalogs")
    plan = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                  prepared_root: prepared, stage_kind: "task_extension")
    assert_equal 1, plan.fetch("assigned_cells")
    assert_equal "prepared", plan.fetch("cells").first.fetch("status")
    assert_equal "demo", JSON.parse(File.read(File.join(output, "grid.json"))).fetch("cells").first.fetch("task")
    assert_equal 2, JSON.parse(File.read(File.join(prepared, "0001", "stage2-manifest.json"))).fetch("repeat")
    assert_includes plan.fetch("next").fetch("command"), "llmx-contrast-v2-minimal:20261102"
    assert_includes plan.fetch("next").fetch("command"), "--auth-file /auth/codex"
    refute plan.fetch("next").fetch("command").include?("--condition base")
    assert_equal File.join(output, "0001"), plan.fetch("next").fetch("command_argv")[plan.fetch("next").fetch("command_argv").index("--output") + 1]
    assert_equal 1, plan.fetch("status_counts").fetch("prepared")
    refute prepared.start_with?(output + File::SEPARATOR)
  end

  def test_grid_driver_marks_unstable_source_blocked_without_dropping_assignment
    source_grid = make_grid_for(@trial, stable: false)
    output = File.join(@tmp, "blocked-grid")
    plan = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                  prepared_root: File.join(@tmp, "blocked-prepared"), stage_kind: "clarification")
    assert_equal "blocked", plan.fetch("cells").first.fetch("status")
    assert_equal 1, JSON.parse(File.read(File.join(output, "grid.json"))).fetch("cells").length
    sidecar = JSON.parse(File.read(File.join(output, "stage2-blocked", "0001.json")))
    assert_includes sidecar.fetch("reason"), "not stable"
  end

  def test_grid_driver_emits_resume_helper_for_unresolved_clarification_without_answering
    source_grid = make_grid_for(@trial, status: "awaiting_review")
    meta_path = File.join(source_grid, "0001", "meta.json")
    source_meta = JSON.parse(File.read(meta_path)).merge("agent_run" => {"seconds" => 300})
    File.write(meta_path, JSON.pretty_generate(source_meta))
    output = File.join(@tmp, "clarification-grid")
    plan = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                  prepared_root: File.join(@tmp, "clarification-prepared"), stage_kind: "clarification")
    next_cell = plan.fetch("next")
    assert_equal "clarification_required", next_cell.fetch("status")
    assert_includes next_cell.fetch("command"), File.realpath(File.join(__dir__, "..", "support", "resume.rb"))
    assert_equal File.join(File.realpath(source_grid), "0001", "continuations", "answer1"), next_cell.fetch("continuation_output")
    assert_equal 600, next_cell.fetch("stage_budget_remaining_seconds")
    assert_equal "600", next_cell.fetch("command_argv").last
    refute File.exist?(next_cell.fetch("response_file_to_prepare"))
    assert_includes next_cell.fetch("instruction"), "does not generate the response"
    assert_equal 1, JSON.parse(File.read(File.join(output, "grid.json"))).fetch("cells").length

    source_meta_path = File.join(source_grid, "0001", "meta.json")
    source_meta = JSON.parse(File.read(source_meta_path)).merge("status" => "complete")
    File.write(source_meta_path, JSON.pretty_generate(source_meta))
    resumed = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                     prepared_root: File.join(@tmp, "clarification-prepared"),
                                     stage_kind: "clarification", resume: true)
    assert_equal "prepared", resumed.fetch("cells").first.fetch("status")
  end

  def test_stage2_clarification_budget_excludes_stage1_execution_chain
    stage1 = @trial
    stage1_meta = JSON.parse(File.read(File.join(stage1, "meta.json"))).merge("agent_run" => {"seconds" => 500})
    File.write(File.join(stage1, "meta.json"), JSON.pretty_generate(stage1_meta))
    stage2 = File.join(@tmp, "stage2-cell")
    FileUtils.mkdir_p(stage2)
    stage2_meta = stage1_meta.merge("status" => "awaiting_review", "stage" => 2, "session_id" => "stage2-session",
                                    "stage1_source_trial" => stage1, "agent_run" => {"seconds" => 200})
    File.write(File.join(stage2, "meta.json"), JSON.pretty_generate(stage2_meta))
    child = File.join(stage2, "continuations", "clarification-1")
    FileUtils.mkdir_p(child)
    child_meta = stage2_meta.merge("source_trial" => stage2, "agent_run" => {"seconds" => 100})
    File.write(File.join(child, "meta.json"), JSON.pretty_generate(child_meta))

    entry = ContrastV2Grid.clarification_entry({"task" => "demo"}, 0, child, child_meta, "/tmp/resume.rb", @tmp)
    assert_equal 300, entry.fetch("stage_budget_used_seconds")
    assert_equal 600, entry.fetch("stage_budget_remaining_seconds")
    assert_equal "600", entry.fetch("command_argv").last
    assert_equal child, entry.fetch("resume_source_trial")
    refute entry.key?("stage1_source_trial")
  end

  def test_second_clarification_is_a_sibling_seen_by_gridsummary
    source_grid = make_grid_for(@trial, status: "awaiting_review")
    root = File.join(source_grid, "0001")
    root_meta = JSON.parse(File.read(File.join(root, "meta.json"))).merge("agent_run" => {"seconds" => 100}, "session_id" => "s1")
    File.write(File.join(root, "meta.json"), JSON.pretty_generate(root_meta))
    first = File.join(root, "continuations", "answer1")
    FileUtils.mkdir_p(first)
    first_meta = root_meta.merge("source_trial" => root, "status" => "awaiting_review", "session_id" => "s2", "agent_run" => {"seconds" => 200})
    File.write(File.join(first, "meta.json"), JSON.pretty_generate(first_meta))
    response = ContrastV2Grid.clarification_entry({"task" => "demo"}, 0, first, first_meta, "/tmp/resume.rb", source_grid)
    second = response.fetch("continuation_output")
    assert_equal File.join(File.realpath(root), "continuations", "answer2"), second
    refute_equal File.join(first, "continuations", "answer2"), second

    FileUtils.mkdir_p(second)
    second_meta = first_meta.merge("source_trial" => first, "status" => "complete", "session_id" => "s3",
                                   "agent_run" => {"seconds" => 50}, "checks_passed" => true, "restoration_verified" => true)
    File.write(File.join(second, "meta.json"), JSON.pretty_generate(second_meta))
    FileUtils.cp(File.join(root, "snapshot.json"), second)
    FileUtils.cp(File.join(root, "checks.json"), second)
    FileUtils.cp(File.join(root, "baseline.bundle"), second)
    FileUtils.cp(File.join(root, "final.bundle"), second)
    summary = GridSummary.build(source_grid).fetch("cells").first
    assert_equal "complete", summary.fetch("disposition")
    assert_equal "0001/continuations/answer2", summary.fetch("final_path")
  end

  def test_grid_driver_resume_skips_already_completed_stage2_cells
    source_grid = make_grid_for(@trial)
    output = File.join(@tmp, "resumable-grid")
    prepared = File.join(@tmp, "resumable-prepared")
    ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                           prepared_root: prepared, stage_kind: "task_extension")
    command = [RbConfig.ruby, File.join(__dir__, "..", "run_stage2.rb"), "--prepared", File.join(prepared, "0001"),
               "--task", "demo", "--agent", "codex", "--condition", "treatment", "--model", "model",
               "--track", "specified", "--output", File.join(output, "0001"), "--fake-command", "/usr/bin/true"]
    _stdout, stderr, status = Open3.capture3(*command)
    assert status.success?, stderr
    meta = JSON.parse(File.read(File.join(output, "0001", "meta.json")))
    assert_equal 2, meta.fetch("repeat")
    plan = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                  prepared_root: prepared, stage_kind: "task_extension", resume: true)
    assert_equal "needs_review", plan.fetch("cells").first.fetch("status")
    assert_nil plan.fetch("next")
    assert_equal "needs_review", plan.fetch("cells").first.fetch("status")
    assert_equal "fake", plan.fetch("cells").first.fetch("stage2_disposition")
  end

  def test_grid_driver_blocks_stale_prepared_catalog_when_clarification_changes_source_path
    source_grid = make_grid_for(@trial)
    output = File.join(@tmp, "stale-grid")
    prepared = File.join(@tmp, "stale-prepared")
    first_plan = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                        prepared_root: prepared, stage_kind: "task_extension")
    original_source = first_plan.fetch("cells").first.fetch("stage1_final_path")
    cell = File.join(source_grid, "0001")
    root_meta_path = File.join(cell, "meta.json")
    root_meta = JSON.parse(File.read(root_meta_path)).merge("status" => "awaiting_review", "session_id" => "review-session")
    File.write(root_meta_path, JSON.pretty_generate(root_meta))
    child = File.join(cell, "continuations", "clarification-1")
    FileUtils.mkdir_p(child)
    FileUtils.cp_r(Dir.children(@trial).map { |entry| File.join(@trial, entry) }, child)
    child_meta_path = File.join(child, "meta.json")
    child_meta = JSON.parse(File.read(child_meta_path)).merge("source_trial" => cell, "status" => "complete")
    File.write(child_meta_path, JSON.pretty_generate(child_meta))

    resumed = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                     prepared_root: prepared, stage_kind: "task_extension", resume: true)
    assert_equal "blocked", resumed.fetch("cells").first.fetch("status")
    assert_equal original_source, JSON.parse(File.read(File.join(prepared, "0001", "stage2-manifest.json"))).fetch("stage1_source_trial")
    blocked = JSON.parse(File.read(File.join(output, "stage2-blocked", "0001.json")))
    assert_includes blocked.fetch("reason"), "prepared source differs"
  end

  def test_root_protocol_deviation_blocks_assignment_even_when_final_continuation_is_stable
    source_grid = make_grid_for(@trial, status: "awaiting_review")
    root = File.join(source_grid, "0001")
    root_meta_path = File.join(root, "meta.json")
    root_meta = JSON.parse(File.read(root_meta_path))
    root_meta["status"] = "awaiting_review"
    File.write(root_meta_path, JSON.pretty_generate(root_meta))
    root_meta_before = File.read(root_meta_path)
    File.write(File.join(root, "protocol-deviation.json"), JSON.pretty_generate(
      "classification" => "invalidoperator-source", "eligible_behavioral_trial" => false,
      "reason" => "controller supplied unsupported facts"
    ))
    final = File.join(root, "continuations", "answer1")
    FileUtils.mkdir_p(final)
    FileUtils.cp_r(Dir.children(@trial).map { |entry| File.join(@trial, entry) }, final)
    final_meta_path = File.join(final, "meta.json")
    final_meta = JSON.parse(File.read(final_meta_path)).merge("source_trial" => root, "status" => "task_failure")
    File.write(final_meta_path, JSON.pretty_generate(final_meta))

    output = File.join(@tmp, "operator-flag-grid")
    prepared = File.join(@tmp, "operator-flag-prepared")
    first = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                   prepared_root: prepared, stage_kind: "task_extension")
    assert_equal "task_failure", GridSummary.build(source_grid).fetch("cells").first.fetch("disposition")
    assert_equal "blocked", first.fetch("cells").first.fetch("status")
    assert_equal File.realpath(final), first.fetch("cells").first.fetch("stage1_source_trial")
    assert_includes first.fetch("cells").first.fetch("reason"), "invalidoperator-source"
    refute File.exist?(File.join(prepared, "0001"))
    assert_equal 1, JSON.parse(File.read(File.join(output, "grid.json"))).fetch("cells").length

    resumed = ContrastV2Grid.prepare(stage1_root: source_grid, catalog: @catalog, output: output,
                                     prepared_root: prepared, stage_kind: "task_extension", resume: true)
    assert_equal "blocked", resumed.fetch("cells").first.fetch("status")
    refute File.exist?(File.join(prepared, "0001"))
    assert_equal root_meta_before, File.read(root_meta_path)
  end
end
