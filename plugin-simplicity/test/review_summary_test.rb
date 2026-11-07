# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/review_summary"

class ReviewSummaryTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("review-summary")
    @root = File.join(@tmp, "reports", "pilot-test")
    @batch_root = File.join(@root, "review-report")
    @packet_dir = File.join(@batch_root, "packets")
    @reviews = File.join(@root, "automated-review")
    FileUtils.mkdir_p([@packet_dir, @reviews])
    File.write(File.join(@root, "code-index.md"), "index\n")
    write_json(File.join(@batch_root, "private-key.json"), {
      "packets" => {
        "R-0001" => {"grid_cell" => "0011", "final_trial" => "0011", "task" => "report", "agent" => "codex", "condition" => "plain", "track" => "specified"},
        "R-0002" => {"grid_cell" => "0012", "final_trial" => "0012", "task" => "report", "agent" => "claude", "condition" => "rubypowers", "track" => "specified"}
      }
    })
    %w[R-0001 R-0002].each { |id| File.write(File.join(@packet_dir, "#{id}.md"), "Blinded packet\n") }
    write_ratings("luna", [rating("R-0001", 3), rating("R-0002", 2)])
    write_ratings("terra", [rating("R-0001", 3), rating("R-0002", 4)])
  end

  def teardown
    FileUtils.remove_entry(@tmp) if File.exist?(@tmp)
  end

  def test_preserves_disagreement_and_reports_no_winner
    output = File.join(@root, "derived")
    ReviewSummary.write(@root, output)
    findings = JSON.parse(File.read(File.join(output, "review-findings.json")))
    report_batch = findings.fetch("batches").find { |batch| batch.fetch("batch") == "report" }
    packet = report_batch.fetch("packets").find { |row| row.fetch("packet") == "R-0002" }

    assert_equal 2, packet.dig("reviewers", "luna", "scores", "concepts")
    assert_equal 4, packet.dig("reviewers", "terra", "scores", "concepts")
    assert_equal(-2, packet.dig("score_difference_luna_minus_terra", "concepts"))
    assert_equal "pending_reviews", findings.fetch("batches").find { |batch| batch.fetch("batch") == "csv_import" }.fetch("status")
    markdown = File.read(File.join(output, "automated-review.md"))
    assert_includes markdown, "No combined score, rank, or winner"
    assert_includes markdown, "not failed acceptance checks"
    refute_includes markdown, "Overall winner"
  end

  def test_rejects_missing_expected_packet
    write_ratings("luna", [rating("R-0001", 3)])
    error = assert_raises(RuntimeError) { ReviewSummary.build(@root) }
    assert_includes error.message, "missing packet IDs R-0002"
  end

  def test_rejects_duplicate_packet
    write_ratings("luna", [rating("R-0001", 3), rating("R-0001", 4)])
    error = assert_raises(RuntimeError) { ReviewSummary.build(@root) }
    assert_includes error.message, "duplicate packet ratings"
  end

  def test_rejects_invalid_score
    row = rating("R-0001", 6)
    write_ratings("luna", [row, rating("R-0002", 4)])
    error = assert_raises(RuntimeError) { ReviewSummary.build(@root) }
    assert_includes error.message, "integer from 1 to 5"
  end

  def test_does_not_overwrite_output
    output = File.join(@root, "derived")
    Dir.mkdir(output)
    File.write(File.join(output, "keep"), "original")
    assert_raises(RuntimeError) { ReviewSummary.write(@root, output) }
    assert_equal "original", File.read(File.join(output, "keep"))
  end

  def test_continuation_workspace_resolves_to_original_cell_workspace
    results = File.join(@tmp, "results-raw", "pilot-test")
    workspace = File.join(results, "0012", "workspace")
    continuation = File.join(results, "0012", "continuations", "answer-02")
    FileUtils.mkdir_p([workspace, continuation])
    write_json(File.join(continuation, "meta.json"), {"workspace_path" => workspace})
    mapping = {
      "grid_cell" => "0012", "final_trial" => "0012/continuations/answer-02",
      "task" => "report", "agent" => "claude", "condition" => "rubypowers", "track" => "specified"
    }
    write_json(File.join(@batch_root, "private-key.json"), {"packets" => {"R-0002" => mapping}})
    File.delete(File.join(@packet_dir, "R-0001.md"))
    write_ratings("luna", [rating("R-0002", 2)])
    write_ratings("terra", [rating("R-0002", 4)])

    batch = ReviewSummary.build(@root).find { |row| row.fetch("batch") == "report" }
    packet = batch.fetch("packets").first
    expected = Pathname.new(workspace).relative_path_from(Pathname.new(@root)).to_s
    assert_equal expected, packet.fetch("workspace_path")

    output = File.join(@tmp, "derived")
    ReviewSummary.write(@root, output)
    line = File.readlines(File.join(output, "automated-review.md")).find { |row| row.include?("source index:") }
    assert_match(/source index: \[open\]\([^)]*\)\./, line)
    refute_match(/source index: \[open\]\([^)]*\)\)\./, line)
  end

  private

  def rating(packet, concepts)
    {"packet" => packet, "concepts" => concepts, "boundaries" => 3, "cohesion" => 4, "interfaces" => 2,
     "evidence" => ReviewSummary::DIMENSIONS.to_h { |dimension| [dimension, "Evidence for #{dimension}"] },
     "correctness_concerns" => ["Review question"]}
  end

  def write_ratings(rater, ratings)
    write_json(File.join(@reviews, "report-#{rater}.json"), {"batch" => "report", "reviewer" => rater, "ratings" => ratings})
  end

  def write_json(path, value)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(value))
  end
end
