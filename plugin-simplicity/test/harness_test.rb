require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/harness"

class HarnessTest < Minitest::Test
  def test_continuation_only_uses_exact_preregistered_answers
    assert_equal "yes", Pilot.answer("Question?", {"Question?" => "yes"})
    assert_nil Pilot.answer("May I deploy?", {"Question?" => "yes"})
  end

  def test_timeout_is_recorded
    result = Pilot.command([RbConfig.ruby, "-e", "sleep 5"], timeout: 0.1)
    assert result.fetch("timed_out")
  end

  def test_snapshot_retains_untracked_and_committed_changes_and_restores
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "repo")
      out = File.join(dir, "out")
      FileUtils.mkdir_p([repo, out])
      system("git", "init", "-q", repo, exception: true)
      system("git", "-C", repo, "config", "user.email", "test@example.com", exception: true)
      system("git", "-C", repo, "config", "user.name", "Test", exception: true)
      File.write(File.join(repo, "base"), "base")
      system("git", "-C", repo, "add", ".", exception: true)
      system("git", "-C", repo, "commit", "-qm", "base", exception: true)
      baseline = Pilot.git(repo, "rev-parse", "HEAD").strip
      File.write(File.join(repo, "new"), "new")
      before = Pilot.git(repo, "status", "--porcelain")
      Pilot.snapshot(repo, out, baseline)
      assert_equal before, Pilot.git(repo, "status", "--porcelain")
      assert File.exist?(File.join(out, "final.bundle"))
      assert Pilot.verify_restore(out)
    end
  end

  def test_dry_run_does_not_write
    Dir.mktmpdir do |dir|
      output = File.join(dir, "out")
      Pilot.dry_run({"task" => "example", "output" => output})
      refute File.exist?(output)
    end
  end
end

class TrialIntegrationTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @catalog = File.join(@dir, "catalog")
    FileUtils.mkdir_p(File.join(@catalog, "fixture"))
    File.write(File.join(@catalog, "fixture", "app.rb"), "puts :original\n")
    File.write(File.join(@catalog, "prompt.txt"), "hello")
    File.write(File.join(@catalog, "tasks.json"), JSON.generate([{id: "task", fixture: "fixture", prompt: {natural: "prompt.txt", specified: "prompt.txt"}, answers: {}, checks: []}]))
    File.write(File.join(@catalog, "conditions.json"), JSON.generate([{id: "baseline", plugin_path: nil}]))
    @fake = File.join(@dir, "fake")
    File.write(@fake, "#!/usr/bin/env ruby\nFile.write('created.rb', 'created')\nexit 3\n")
    FileUtils.chmod(0755, @fake)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_failure_retains_workspace_and_restorable_snapshot
    out = File.join(@dir, "out")
    trial = File.expand_path("../scripts/run_trial.rb", __dir__)
    system(RbConfig.ruby, trial, "--catalog", @catalog, "--output", out, "--task", "task", "--agent", "codex", "--model", "fake", "--condition", "baseline", "--track", "specified", "--fake-command", @fake, out: File::NULL)
    meta = JSON.parse(File.read(File.join(out, "meta.json")))
    assert_equal "agent_failure", meta["status"]
    assert meta["restoration_verified"]
    assert File.exist?(File.join(out, "workspace", "created.rb"))
  end

  def test_checks_run_against_restored_baseline_tests
    FileUtils.mkdir_p(File.join(@catalog, "fixture", "test"))
    File.write(File.join(@catalog, "fixture", "test", "check.rb"), "abort unless File.read(\"app.rb\").include?(\"original\")\n")
    catalog_path = File.join(@catalog, "tasks.json")
    tasks = JSON.parse(File.read(catalog_path))
    tasks.first["checks"] = [[RbConfig.ruby, "test/check.rb"]]
    File.write(catalog_path, JSON.generate(tasks))
    File.write(@fake, "#!/usr/bin/env ruby\nFile.write(\"test/check.rb\", \"exit 1\")\n")
    out = File.join(@dir, "out")
    trial = File.expand_path("../scripts/run_trial.rb", __dir__)
    assert system(RbConfig.ruby, trial, "--catalog", @catalog, "--output", out, "--task", "task", "--agent", "codex", "--model", "fake", "--condition", "baseline", "--track", "specified", "--fake-command", @fake, out: File::NULL)
    meta = JSON.parse(File.read(File.join(out, "meta.json")))
    assert meta["checks_passed"]
    assert_equal "exit 1", File.read(File.join(out, "workspace", "test", "check.rb"))
  end

  def test_grid_dry_run_has_all_cells_without_output
    out = File.join(@dir, "grid")
    grid = File.expand_path("../scripts/run_grid.rb", __dir__)
    output, status = Open3.capture2(RbConfig.ruby, grid, "--catalog", @catalog, "--output", out, "--claude-model", "fake", "--codex-model", "fake", "--tasks", "task", "--dry-run")
    assert status.success?
    assert_equal 8, JSON.parse(output).fetch("cells").size
    refute File.exist?(out)
  end
end
