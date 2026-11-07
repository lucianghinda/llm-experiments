# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "minitest/mock"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../scripts/report"

class PilotReportTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("pilot-report-test")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_claude_uses_aggregate_result_usage_and_does_not_print_transcript
    transcript = File.join(@root, "transcript.txt")
    File.write(transcript, [
      {"type" => "assistant", "message" => {"usage" => {"input_tokens" => 500, "output_tokens" => 50}}},
      {"type" => "result", "usage" => {"input_tokens" => 200, "output_tokens" => 20, "cache_read_input_tokens" => 40, "cache_creation_input_tokens" => 10}, "total_cost_usd" => 0.012}
    ].map(&:to_json).join("\n") + "\nLEAKED-TRANSCRIPT-TEXT")

    usage = PilotReport.usage_from(transcript, "claude")

    assert_equal 200, usage[:input_tokens]
    assert_equal 20, usage[:output_tokens]
    assert_equal 40, usage[:cache_read_input_tokens]
    assert_equal 10, usage[:cache_creation_input_tokens]
    assert_equal 0.012, usage[:cost_usd]
    refute_includes PilotReport.build(@root), "LEAKED-TRANSCRIPT-TEXT"
  end

  def test_codex_sums_completed_turn_usage_only_and_cost_stays_unknown
    transcript = File.join(@root, "transcript.txt")
    File.write(transcript, [
      {"type" => "item.completed", "usage" => {"input_tokens" => 900, "output_tokens" => 90}},
      {"type" => "turn.completed", "usage" => {"input_tokens" => 100, "cached_input_tokens" => 30, "output_tokens" => 12}},
      {"type" => "turn.completed", "usage" => {"input_tokens" => 70, "cached_input_tokens" => 5, "output_tokens" => 8}}
    ].map(&:to_json).join("\n"))

    usage = PilotReport.usage_from(transcript, "codex")

    assert_equal 170, usage[:input_tokens]
    assert_equal 20, usage[:output_tokens]
    assert_equal 35, usage[:cache_read_input_tokens]
    assert_equal "unknown", usage[:cache_creation_input_tokens]
    assert_equal "unknown", usage[:cost_usd]
  end

  def test_codex_missing_turn_field_stays_unknown_and_cache_write_alias_is_used
    events = [
      {"type" => "turn.completed", "usage" => {"input_tokens" => 100, "output_tokens" => 20, "cached_input_tokens" => 30, "cache_write_input_tokens" => 8}},
      {"type" => "turn.completed", "usage" => {"input_tokens" => 50, "cached_input_tokens" => 10, "cache_write_input_tokens" => 4}}
    ]

    usage = PilotReport.codex_usage(events)

    assert_equal 150, usage[:input_tokens]
    assert_equal "unknown", usage[:output_tokens]
    assert_equal 40, usage[:cache_read_input_tokens]
    assert_equal 12, usage[:cache_creation_input_tokens]
  end

  def test_report_retains_failed_and_fake_attempts_and_reports_diagnostic_diff_counts
    trial = create_trial("natural/failed", fake: false)
    add_bundle_changes(trial)
    verification = File.join(trial, "verification-attempts", "original")
    FileUtils.mkdir_p(verification)
    File.write(File.join(verification, "meta.json"), JSON.generate("status" => "awaiting_review", "condition" => "audit-copy"))
    create_trial("specified/fake", fake: true)

    report = PilotReport.build(@root)

    assert_includes report, "natural/failed"
    refute_includes report, "natural/failed/verification-attempts/original"
    assert_includes report, "specified/fake"
    assert_includes report, "excluded (fake adapter)"
    assert_includes report, "awaiting_review"
    assert_includes report, "not quality scores"
    assert_includes report, "excluded (fake adapter)"
    refute_includes report, "transcript secret"
    assert_includes report, "| production | 0 | 0 | 1 | 1 | 0 |"
    assert_includes report, "| tests | 1 | 0 | 0 | 1 | 0 |"
    assert_includes report, "| docs | 0 | 0 | 1 | 1 | 0 |"
  end

  def test_missing_usage_and_cost_are_unknown_not_zero
    File.write(File.join(@root, "transcript.txt"), "{}\n")

    usage = PilotReport.usage_from(File.join(@root, "transcript.txt"), "claude")

    assert_equal "unknown", usage[:input_tokens]
    assert_equal "unknown", usage[:output_tokens]
    assert_equal "unknown", usage[:cost_usd]
  end

  def test_root_test_support_file_is_counted_as_test_code
    assert_equal :tests, PilotReport.category("test_support.rb")
    assert_equal :production, PilotReport.category("app/service.rb")
  end

  def test_diff_cleanup_failure_keeps_trial_metadata_and_marks_counts_unknown
    trial = create_trial("codex-rubypowers-01", fake: false)
    add_bundle_changes(trial)
    report = Dir.stub(:mktmpdir, ->(*) { raise Errno::ENOTEMPTY, "directory not empty" }) do
      PilotReport.report_trial("codex-rubypowers-01", trial)
    end

    assert_equal "awaiting_review", report[:status]
    assert_equal "campfire_feature", report[:task]
    assert_equal "behavioral attempt", report[:eligibility]
    assert_match(/Errno::ENOTEMPTY/, report[:change_error])
    assert_equal "unknown", report[:changes][:production][:added_files]
  end

  def test_setup_failures_and_continuation_audits_are_not_behavioral_trials
    setup_trial = create_trial("codex/setup", fake: false)
    setup_meta_path = File.join(setup_trial, "meta.json")
    setup_meta = JSON.parse(File.read(setup_meta_path)).merge("status" => "infrastructure_failure")
    File.write(setup_meta_path, JSON.generate(setup_meta))
    continuation = create_trial("claude-continuation-01", fake: false)
    continuation_meta_path = File.join(continuation, "meta.json")
    continuation_meta = JSON.parse(File.read(continuation_meta_path)).merge("task" => "continuation_smoke")
    File.write(continuation_meta_path, JSON.generate(continuation_meta))

    assert_equal "excluded (setup failure)", PilotReport.report_trial("codex/setup", setup_trial)[:eligibility]
    assert_equal "excluded (continuation/audit)", PilotReport.report_trial("claude-continuation-01", continuation)[:eligibility]
  end

  def test_real_continuation_turn_is_part_of_its_existing_cell
    trial = create_trial("codex-baseline-01/continuations/answer-01", fake: false)
    report = PilotReport.report_trial("codex-baseline-01/continuations/answer-01", trial)

    assert_equal "part of existing cell (continuation; not an additional trial)", report[:eligibility]
    rendered = PilotReport.render([report])
    assert_includes rendered, "The attempts table is not the assigned-cell denominator"
    assert_includes rendered, "included via existing cell"
    assert_includes rendered, "final continuation code and agent time are included in the cell comparison"
  end

  def test_incident_sidecar_overrides_raw_agent_failure_without_mutating_meta
    trial = create_trial("codex-continuation-01/continuations/answer-01", fake: false)
    meta_path = File.join(trial, "meta.json")
    meta = JSON.parse(File.read(meta_path)).merge("status" => "agent_failure", "task" => "continuation_smoke")
    File.write(meta_path, JSON.generate(meta))
    File.write(File.join(trial, "incident.json"), JSON.generate({
      "classification" => "infrastructure_failure",
      "eligible_behavioral_trial" => false,
      "summary" => "Linux kernel Oops and persistent RCU stalls during container execution"
    }))

    report = PilotReport.report_trial("codex-continuation-01/continuations/answer-01", trial)

    assert_equal "agent_failure", report[:status]
    assert_equal "infrastructure_failure", report[:incident]
    assert_equal "excluded (infrastructure incident)", report[:eligibility]
    assert_equal "agent_failure", JSON.parse(File.read(meta_path))["status"]
  end

  private

  def create_trial(relative, fake:)
    trial = File.join(@root, relative)
    FileUtils.mkdir_p(trial)
    meta = {
      "task" => "campfire_feature",
      "agent" => "claude",
      "model" => "synthetic-model",
      "condition" => "plainspoken",
      "track" => "natural",
      "status" => fake ? "fake_complete" : "awaiting_review",
      "adapter" => fake ? "fake" : "container",
      "restoration_verified" => true,
      "agent_run" => {"seconds" => 12.5}
    }
    File.write(File.join(trial, "meta.json"), JSON.pretty_generate(meta))
    File.write(File.join(trial, "checks.json"), JSON.generate([{"exit" => 0, "timed_out" => false}]))
    File.write(File.join(trial, "transcript.txt"), "transcript secret must not appear in report")
    trial
  end

  def add_bundle_changes(trial)
    repo = File.join(@root, "synthetic-repo")
    FileUtils.mkdir_p(repo)
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "Report Test")
    git(repo, "config", "user.email", "report@example.invalid")
    write(repo, "app/service.rb", "class Service\nend\n")
    write(repo, "README.md", "before\n")
    commit(repo, "baseline")
    baseline = git(repo, "rev-parse", "HEAD").strip
    git(repo, "update-ref", "refs/pilot/baseline", baseline)
    git(repo, "bundle", "create", File.join(trial, "baseline.bundle"), "refs/pilot/baseline")

    write(repo, "app/service.rb", "class Service\n  def call; end\nend\n")
    write(repo, "test/service_test.rb", "assert true\n")
    write(repo, "README.md", "before\nafter\n")
    commit(repo, "final")
    final = git(repo, "rev-parse", "HEAD").strip
    git(repo, "update-ref", "refs/pilot/final", final)
    git(repo, "bundle", "create", File.join(trial, "final.bundle"), "refs/pilot/final")
    File.write(File.join(trial, "snapshot.json"), JSON.generate("baseline" => baseline, "final" => final))
  end

  def write(repo, path, contents)
    target = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, contents)
  end

  def commit(repo, message)
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", message)
  end

  def git(repo, *args)
    output, error, status = Open3.capture3("git", "-C", repo, *args)
    raise error unless status.success?

    output
  end
end
