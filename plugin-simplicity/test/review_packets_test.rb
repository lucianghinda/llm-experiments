# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../scripts/review_packets"

class ReviewPacketsTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("review-packet-test")
    @output = File.join(@root, "packets-a")
    @results = File.join(@root, "results")
    FileUtils.mkdir_p(@results)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_packets_are_blinded_randomized_and_private_mapping_is_separate
    create_trial("cell-a", condition: "ruby-plainspoken", agent: "codex", model: "secret-model")
    create_trial("cell-b", condition: "baseline", agent: "claude", model: "other-secret")
    verification = File.join(@results, "cell-a", "verification-attempts", "original")
    FileUtils.mkdir_p(verification)
    File.write(File.join(verification, "meta.json"), JSON.generate("status" => "agent_failure", "condition" => "backup"))

    result = ReviewPackets.build(@results, @output, seed: 77)
    packet_text = Dir[File.join(@output, "packets", "*.md")].map { |path| File.read(path) }.join
    key = JSON.parse(File.read(File.join(@output, "private-key.json")))

    assert_equal 2, result[:packet_count]
    assert_equal 2, result[:outcome_count]
    assert_equal 2, key.fetch("packets").length
    assert_includes packet_text, "Concepts"
    assert_includes packet_text, "Production patch"
    assert_includes packet_text, "Trial metadata records passing final acceptance checks"
    refute_match(/ruby-plainspoken|rubypowers|codex|claude|secret-model|plugin instructions|prompt text/i, packet_text)
    refute_includes packet_text, "test_app.rb"
    refute_includes packet_text, "README.md"
    refute_includes packet_text, "docs/guide.rb"
    refute_includes packet_text, "vendor/helper.rb"
    refute_includes packet_text, ".codex/guide.rb"
    assert_equal 0o600, File.stat(File.join(@output, "private-key.json")).mode & 0o777
    assert_equal 0o600, File.stat(File.join(@output, "outcomes.md")).mode & 0o777

    repeated = File.join(@root, "packets-b")
    ReviewPackets.build(@results, repeated, seed: 77)
    assert_equal Dir[File.join(@output, "packets", "*.md")].map { |p| File.basename(p) },
      Dir[File.join(repeated, "packets", "*.md")].map { |p| File.basename(p) }
    assert_equal key, JSON.parse(File.read(File.join(repeated, "private-key.json")))
  end

  def test_neutral_contract_is_included_only_when_supplied
    create_trial("cell", condition: "baseline")
    contracts = File.join(@root, "contracts.json")
    File.write(contracts, JSON.generate("report" => "Return a count and total; optional status filters both."))

    ReviewPackets.build(@results, @output, seed: 3, contracts: contracts)

    packet = File.read(Dir[File.join(@output, "packets", "*.md")].first)
    assert_includes packet, "Neutral behavior contract"
    assert_includes packet, "optional status filters both"
    refute_includes packet, "ruby-plainspoken"
  end

  def test_without_contract_packet_discloses_the_context_limitation
    create_trial("cell", condition: "baseline")

    ReviewPackets.build(@results, @output, seed: 3)

    packet = File.read(Dir[File.join(@output, "packets", "*.md")].first)
    assert_includes packet, "No neutral behavior contract was supplied"
  end

  def test_production_filter_excludes_docs_vendor_and_workflow_trees_even_for_ruby
    %w[docs/guide.rb doc/guide.rb vendor/tool.rb .agents/skill.rb .claude/skill.rb .codex/skill.rb .omx/skill.rb test_helper.rb helper_spec.rb app/domain.rb].each do |path|
      included = ReviewPackets.production_code?(path)
      expected = path == "app/domain.rb"
      assert_equal expected, included, path
    end
  end

  def test_failed_attempts_stay_in_private_outcome_table_but_do_not_get_scored
    create_trial("cell-good", condition: "baseline")
    create_trial("cell-failed", condition: "ruby-plainspoken", checks_passed: false)

    ReviewPackets.build(@results, @output, seed: 1)

    assert_equal 1, Dir[File.join(@output, "packets", "*.md")].length
    outcomes = File.read(File.join(@output, "outcomes.md"))
    assert_includes outcomes, "cell-failed"
    assert_includes outcomes, "checks are not all passing"
    refute_includes Dir[File.join(@output, "packets", "*.md")].map { |p| File.read(p) }.join, "cell-failed"
  end

  def test_stable_failed_packets_require_explicit_owner_final_list_and_keep_status_private
    task_failure = create_trial("cell-task-failure", condition: "baseline", status: "awaiting_review", checks_passed: false)
    timeout = create_trial("cell-timeout", condition: "baseline", status: "timeout", checks_passed: false)
    mark_stable_failure(task_failure, category: "task_failure")
    mark_stable_failure(timeout, category: "timeout")
    finals = File.join(@root, "stable-failures.txt")
    File.write(finals, "cell-task-failure\ncell-timeout\n")

    default_error = assert_raises(RuntimeError) do
      ReviewPackets.build(@results, @output, seed: 1, final_trials: finals)
    end
    assert_match(/listed trial is not validated/, default_error.message)
    refute File.exist?(@output)

    error = assert_raises(RuntimeError) do
      ReviewPackets.build(@results, @output, seed: 1, include_stable_failures: true)
    end
    assert_match(/requires an explicit --final-trials/, error.message)
    refute File.exist?(@output)

    result = ReviewPackets.build(@results, @output, seed: 1, final_trials: finals, include_stable_failures: true)

    assert_equal 2, result[:packet_count]
    packet_text = Dir[File.join(@output, "packets", "*.md")].map { |path| File.read(path) }.join
    refute_includes packet_text, "passing final acceptance checks"
    assert_includes packet_text, "Trial metadata is not included"
    refute_includes packet_text, "awaiting_review"
    refute_includes packet_text, "timeout"
    outcomes = File.read(File.join(@output, "outcomes.md"))
    assert_includes outcomes, "owner-selected stable failed outcome"
    assert_includes outcomes, "awaiting_review"
    assert_includes outcomes, "timeout"
  end

  def test_unstable_or_unrestored_failure_is_excluded_with_private_owner_note
    trial = create_trial("cell-unstable", condition: "baseline", status: "awaiting_review", checks_passed: false)
    mark_stable_failure(trial, category: "task_failure", workspace_stable: false)
    finals = File.join(@root, "unstable.txt")
    File.write(finals, "cell-unstable\n")

    result = ReviewPackets.build(@results, @output, seed: 1, final_trials: finals, include_stable_failures: true)

    assert_equal 0, result[:packet_count]
    outcomes = File.read(File.join(@output, "outcomes.md"))
    assert_includes outcomes, "manual owner review: workspace stability not verified"
    refute_includes Dir[File.join(@output, "packets", "*.md")].map { |path| File.read(path) }.join, "awaiting_review"
  end

  def test_hash_bound_disposition_and_bundle_integrity_are_required
    stale = create_trial("cell-stale", condition: "baseline", status: "awaiting_review", checks_passed: false)
    pending = create_trial("cell-pending", condition: "baseline", status: "awaiting_review", checks_passed: false)
    broken = create_trial("cell-broken-bundle", condition: "baseline", status: "awaiting_review", checks_passed: false)
    mark_stable_failure(stale, category: "task_failure")
    mark_stable_failure(pending, category: "task_failure")
    mark_stable_failure(broken, category: "task_failure")
    stale_disposition_path = File.join(stale, "disposition.json")
    stale_disposition = JSON.parse(File.read(stale_disposition_path))
    stale_disposition["meta_sha256"] = "stale"
    File.write(stale_disposition_path, JSON.generate(stale_disposition))
    pending_disposition_path = File.join(pending, "disposition.json")
    pending_disposition = JSON.parse(File.read(pending_disposition_path))
    pending_disposition["no_pending_question"] = false
    File.write(pending_disposition_path, JSON.generate(pending_disposition))
    File.write(File.join(broken, "final.bundle"), "broken bundle")
    finals = File.join(@root, "invalid-stable-failures.txt")
    File.write(finals, "cell-stale\ncell-pending\ncell-broken-bundle\n")

    result = ReviewPackets.build(@results, @output, seed: 1, final_trials: finals, include_stable_failures: true)

    assert_equal 0, result[:packet_count]
    outcomes = File.read(File.join(@output, "outcomes.md"))
    assert_includes outcomes, "disposition does not confirm no pending question"
    assert_includes outcomes, "disposition is not bound to current metadata"
    assert_includes outcomes, "manual owner review: snapshot/bundle evidence invalid"
  end

  def test_duplicate_final_paths_for_one_cell_remain_rejected_in_stable_failure_mode
    trial = create_trial("cell", condition: "baseline", status: "awaiting_review", checks_passed: false)
    mark_stable_failure(trial, category: "task_failure")
    finals = File.join(@root, "duplicates.txt")
    File.write(finals, "cell\ncell\n")

    error = assert_raises(RuntimeError) do
      ReviewPackets.build(@results, @output, seed: 1, final_trials: finals, include_stable_failures: true)
    end
    assert_match(/more than one record for a grid cell/, error.message)
    refute File.exist?(@output)
  end

  def test_final_continuation_is_selected_as_same_grid_cell
    parent = create_trial("cell-with-continuation", condition: "baseline", status: "awaiting_review", checks_passed: false)
    create_trial("cell-with-continuation/continuations/answer-01", condition: "continuation_smoke", task: "continuation_smoke", source_trial: parent)
    list = File.join(@root, "finals.txt")
    File.write(list, "cell-with-continuation/continuations/answer-01\n")
    ReviewPackets.build(@results, @output, seed: 4, final_trials: list)

    key = JSON.parse(File.read(File.join(@output, "private-key.json"))).fetch("packets")
    assert_equal "cell-with-continuation", key.values.first.fetch("grid_cell")
    assert_equal "cell-with-continuation/continuations/answer-01", key.values.first.fetch("final_trial")
    packet = File.read(Dir[File.join(@output, "packets", "*.md")].first)
    assert_includes packet, "def call = :old"
    assert_includes packet, "def call = :new_2"
  end

  def test_ambiguous_continuation_branches_require_explicit_final_trial_list
    parent = create_trial("cell", condition: "baseline", status: "awaiting_review", checks_passed: false)
    create_trial("cell/continuations/a", condition: "continuation_smoke", task: "continuation_smoke", source_trial: parent)
    create_trial("cell/continuations/b", condition: "continuation_smoke", task: "continuation_smoke", source_trial: parent)

    error = assert_raises(RuntimeError) { ReviewPackets.build(@results, @output, seed: 4) }
    assert_match(/require an explicit --final-trials/, error.message)
    refute File.exist?(@output)
  end

  def test_existing_output_is_never_overwritten
    create_trial("cell", condition: "baseline")
    FileUtils.mkdir_p(@output)
    marker = File.join(@output, "keep.txt")
    File.write(marker, "keep")

    assert_raises(RuntimeError) { ReviewPackets.build(@results, @output, seed: 1) }
    assert_equal "keep", File.read(marker)
  end

  def test_identifying_code_is_omitted_and_recorded_for_manual_review
    trial = create_trial('labelled', condition: 'baseline')
    repo = @trial_repos.fetch(trial)
    write(repo, 'app.rb', "# Generated with RubyPowers\nclass App; end\n")
    commit(repo, 'labelled')
    final = git(repo, 'rev-parse', 'HEAD').strip
    git(repo, 'update-ref', 'refs/pilot/final', final)
    git(repo, 'bundle', 'create', File.join(trial, 'final.bundle'), 'refs/pilot/final')
    snapshot = JSON.parse(File.read(File.join(trial, 'snapshot.json')))
    File.write(File.join(trial, 'snapshot.json'), JSON.generate(snapshot.merge('final' => final)))
    ReviewPackets.build(@results, @output, seed: 1)
    assert_empty Dir[File.join(@output, 'packets', '*.md')]
    assert_includes File.read(File.join(@output, 'outcomes.md')), 'manual review: possible identifying label'
    assert_includes File.read(File.join(@output, 'PRIVATE-README.txt')), 'Share only the packets/'
  end

  def test_multi_worktree_and_empty_diff_require_manual_review
    multi = create_trial('multi', condition: 'baseline')
    meta_path = File.join(multi, 'meta.json')
    File.write(meta_path, JSON.generate(JSON.parse(File.read(meta_path)).merge('worktrees' => [{}, {}])))
    empty = create_trial('empty', condition: 'baseline')
    snapshot_path = File.join(empty, 'snapshot.json')
    snapshot = JSON.parse(File.read(snapshot_path))
    repo = @trial_repos.fetch(empty)
    git(repo, 'update-ref', 'refs/pilot/final', snapshot.fetch('baseline'))
    git(repo, 'bundle', 'create', File.join(empty, 'final.bundle'), 'refs/pilot/final')
    File.write(snapshot_path, JSON.generate(snapshot.merge('final' => snapshot.fetch('baseline'))))
    ReviewPackets.build(@results, @output, seed: 1)
    assert_empty Dir[File.join(@output, 'packets', '*.md')]
    outcomes = File.read(File.join(@output, 'outcomes.md'))
    assert_includes outcomes, 'manual review: multiple worktrees'
    assert_includes outcomes, 'manual review: no production diff'
  end

  private

  def create_trial(relative, condition:, agent: "claude", model: "private-model", status: "complete", checks_passed: true, task: "report", source_trial: nil)
    path = File.join(@results, relative)
    FileUtils.mkdir_p(path)
    meta = {
      "task" => task,
      "agent" => agent,
      "model" => model,
      "condition" => condition,
      "track" => "specified",
      "status" => status,
      "adapter" => "container",
      "checks_passed" => checks_passed,
      "restoration_verified" => true
    }
    meta["source_trial"] = source_trial if source_trial
    File.write(File.join(path, "meta.json"), JSON.generate(meta))
    check_exit = checks_passed ? 0 : 1
    File.write(File.join(path, "checks.json"), JSON.generate([{"exit" => check_exit, "timed_out" => false}]))
    baseline, final = create_bundles(path, source_trial: source_trial)
    File.write(File.join(path, "snapshot.json"), JSON.generate("baseline" => baseline, "final" => final))
    path
  end

  def create_bundles(trial, source_trial: nil)
    @trial_repos ||= {}
    if source_trial
      repo = @trial_repos.fetch(source_trial)
    else
      repo = File.join(@root, "source-#{@next_repo = (@next_repo || 0) + 1}")
      FileUtils.mkdir_p(repo)
      git(repo, "init", "-q")
      git(repo, "config", "user.name", "Packet Test")
      git(repo, "config", "user.email", "packet@example.invalid")
      write(repo, "app.rb", "class App\n  def call = :old\nend\n")
      write(repo, "README.md", "old\n")
      commit(repo, "baseline")
    end
    @trial_repos[trial] = repo
    baseline = git(repo, "rev-parse", "HEAD").strip
    git(repo, "update-ref", "refs/pilot/baseline", baseline)
    git(repo, "bundle", "create", File.join(trial, "baseline.bundle"), "refs/pilot/baseline")

    @source_revision = (@source_revision || 0) + 1
    write(repo, "app.rb", "class App\n  def call = :new_#{@source_revision}\nend\n")
    write(repo, "test_app.rb", "# tests excluded\n")
    write(repo, "README.md", "new\n")
    write(repo, "docs/guide.rb", "# documentation example\n")
    write(repo, "vendor/helper.rb", "# vendored code\n")
    write(repo, ".codex/guide.rb", "# workflow code\n")
    commit(repo, "final")
    final = git(repo, "rev-parse", "HEAD").strip
    git(repo, "update-ref", "refs/pilot/final", final)
    git(repo, "bundle", "create", File.join(trial, "final.bundle"), "refs/pilot/final")
    [baseline, final]
  end

  def mark_stable_failure(trial, category:, workspace_stable: true)
    meta_path = File.join(trial, "meta.json")
    meta = JSON.parse(File.read(meta_path)).merge(
      "workspace_stable" => workspace_stable,
      "restoration_verified" => true
    )
    File.write(meta_path, JSON.generate(meta))
    repo = @trial_repos.fetch(trial)
    snapshot = JSON.parse(File.read(File.join(trial, "snapshot.json")))
    snapshot["tree"] = git(repo, "rev-parse", "#{snapshot.fetch('final')}^{tree}").strip
    File.write(File.join(trial, "snapshot.json"), JSON.generate(snapshot))
    File.write(File.join(trial, "change.patch"), git(repo, "diff", snapshot.fetch("baseline"), snapshot.fetch("final")))
    disposition = {"category" => category, "meta_sha256" => Digest::SHA256.file(meta_path).hexdigest,
                   "reason" => "owner reviewed terminal outcome", "no_pending_question" => true}
    File.write(File.join(trial, "disposition.json"), JSON.generate(disposition))
  end

  def write(repo, path, text)
    target = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, text)
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
