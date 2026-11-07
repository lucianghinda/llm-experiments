# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

require File.expand_path("/Users/luciang/Dropbox/workprojects/explorations/llm-experiments/plugin-simplicity/scripts/grid_summary.rb")

class GridSummaryNetMetricTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("grid-summary-net-metric")
    @repo = File.join(@tmp, "repo")
    @first = File.join(@tmp, "stage1", "0001")
    @final = File.join(@tmp, "stage2", "0001", "continuations", "final")
    FileUtils.mkdir_p([@repo, @first, @final])
    git("init", "-q")
    git("config", "user.email", "test@example.invalid")
    git("config", "user.name", "Test")
    FileUtils.mkdir_p(File.join(@repo, "lib"))
    File.write(File.join(@repo, "lib", "stable.rb"), "class Stable; end\n")
    git("add", ".")
    git("commit", "-qm", "baseline")
    @baseline = git("rev-parse", "HEAD").strip
    git("update-ref", "refs/pilot/baseline", @baseline)
    File.write(File.join(@repo, "lib", "transient.rb"), "class Transient\n  VALUE = 1\nend\n")
    git("add", ".")
    git("commit", "-qm", "add transient code")
    FileUtils.rm(File.join(@repo, "lib", "transient.rb"))
    git("add", "-A")
    git("commit", "-qm", "remove transient code")
    @final_revision = git("rev-parse", "HEAD").strip
    git("update-ref", "refs/pilot/final", @final_revision)
    git("bundle", "create", File.join(@first, "baseline.bundle"), "refs/pilot/baseline")
    git("bundle", "create", File.join(@final, "final.bundle"), "refs/pilot/final")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_net_final_metric_does_not_add_intermediate_churn
    metrics = GridSummary.solution_metrics(
      {path: @first, snapshot: {"baseline" => @baseline, "final" => @baseline}},
      {path: @final, snapshot: {"baseline" => @baseline, "final" => @final_revision}}
    )

    assert_equal 0, metrics.fetch("production_changed_lines")
  end

  private

  def git(*args)
    stdout, stderr, status = Open3.capture3("git", *args, chdir: @repo)
    raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?
    stdout
  end
end
