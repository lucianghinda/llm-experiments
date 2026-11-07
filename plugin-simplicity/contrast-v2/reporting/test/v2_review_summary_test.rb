# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../v2_review_summary"

class V2ReviewSummaryTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("v2-review-summary")
    @root = File.join(@tmp, "report-root")
    FileUtils.mkdir_p(@root)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_all_twelve_batches_are_explicitly_pending_when_missing
    results = V2ReviewSummary.build(@root)

    assert_equal 12, results.length
    assert_equal 12, results.count { |batch| batch.fetch("status") == "pending_reviews" }
    assert_equal "stage1-notification-natural", results.first.fetch("batch")
    assert_equal "stage2-export-specified", results.last.fetch("batch")
  end

  def test_joined_scores_keep_raters_separate_and_report_disagreement
    batch = "stage1-notification-natural"
    add_mapping(batch, %w[R-0001 R-0002])
    write(File.join(@root, "review-#{batch}", "batch-summary.json"), {
      "exclusions" => [{"reason" => "operator protocol deviation"}, {"reason" => "operator protocol deviation"}, {"reason" => "checker failure"}]
    })
    add_reviews(batch, "luna_a", [score_row("R-0001", 4), score_row("R-0002", 2)])
    add_reviews(batch, "luna_b", [score_row("R-0001", 2), score_row("R-0002", 2)])

    result = V2ReviewSummary.build(@root).find { |row| row.fetch("batch") == batch }
    agreement = result.dig("dimension_agreement", "concepts")
    group = result.fetch("cell_groups").first

    assert_equal "complete", result.fetch("status")
    assert_equal 2, agreement.fetch("paired_packet_count")
    assert_equal 1, agreement.fetch("exact_agreement_count")
    assert_equal 1.0, agreement.fetch("mean_absolute_disagreement")
    assert_equal 3.0, group.dig("per_rater_dimension", "luna_a", "concepts", "median")
    assert_equal 2, group.dig("per_rater_dimension", "luna_b", "concepts", "median")
    assert_equal({"sample_count" => 2, "median" => 3.0}, group.dig("per_rater_dimension", "luna_a", "concepts"))
    assert_equal ["uncovered question, not a failed acceptance check"], result.dig("packets", 0, "correctness_concerns", "luna_a")
    assert_equal 11, V2ReviewSummary.build(@root).count { |row| row.fetch("status") == "pending_reviews" }
    assert_equal 3, result.dig("exclusions", "count")
    assert_equal 2, result.dig("exclusions", "reasons", "operator protocol deviation")
  end

  def test_reviewer_packet_id_mismatch_is_rejected
    batch = "stage2-export-specified"
    add_mapping(batch, ["R-0001"])
    add_reviews(batch, "luna_a", [score_row("R-9999", 3)])

    error = assert_raises(RuntimeError) { V2ReviewSummary.build(@root) }

    assert_match(/missing packet IDs R-0001/, error.message)
  end

  def test_out_of_range_rating_is_rejected
    batch = "stage2-regional-natural"
    add_mapping(batch, ["R-0001"])
    row = score_row("R-0001", 6)
    add_reviews(batch, "luna_a", [row])

    error = assert_raises(RuntimeError) { V2ReviewSummary.build(@root) }

    assert_match(/must be integer 1\.\.5/, error.message)
  end

  def test_markdown_and_json_write_only_to_new_external_directory
    output = File.join(@tmp, "summary")
    V2ReviewSummary.write(@root, output)

    assert File.file?(File.join(output, "v2-review-summary.md"))
    assert File.file?(File.join(output, "v2-review-summary.json"))
    assert_equal 12, JSON.parse(File.read(File.join(output, "v2-review-summary.json"))).fetch("batches").length
    assert_raises(RuntimeError) { V2ReviewSummary.write(@root, output) }
  end

  def test_output_under_input_report_root_is_refused
    output = File.join(@root, "summary")

    error = assert_raises(RuntimeError) { V2ReviewSummary.write(@root, output) }

    assert_match(/outside report inputs/, error.message)
    refute File.exist?(output)
  end

  private

  def add_mapping(batch, ids)
    dir = File.join(@root, "review-#{batch}", "review-packets")
    FileUtils.mkdir_p(File.join(dir, "packets"))
    packets = ids.to_h do |id|
      File.write(File.join(dir, "packets", "#{id}.md"), "blind packet #{id}\n")
      [id, {"task" => batch.split("-")[1], "agent" => "codex", "condition" => "ruby-plainspoken",
            "track" => batch.split("-").last, "grid_cell" => "0042", "final_trial" => "0042/initial"}]
    end
    write(File.join(dir, "private-key.json"), {"packets" => packets})
  end

  def add_reviews(batch, rater, ratings)
    path = File.join(@root, "automated-review", "#{batch}-#{rater}.json")
    write(path, {"batch" => batch, "reviewer" => rater, "ratings" => ratings})
  end

  def score_row(id, score)
    {"packet" => id, "concepts" => score, "boundaries" => score, "cohesion" => score, "interfaces" => score,
     "evidence" => V2ReviewSummary::DIMENSIONS.to_h { |dimension| [dimension, "Observed #{dimension} behavior"] },
     "correctness_concerns" => ["uncovered question, not a failed acceptance check"]}
  end

  def write(path, object)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(object))
  end
end
