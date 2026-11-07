# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

module GridSummary
  def self.build(root)
    JSON.parse(File.read(File.join(root, "summary.json")))
  end
end

module ReviewPackets
  class << self
    attr_accessor :last_call
  end

  def self.load_records(root)
    JSON.parse(File.read(File.join(root, "review-records.json"))).map do |record|
      record.transform_keys(&:to_sym).merge(path: File.realpath(File.join(root, record.fetch("relative"))))
    end
  end

  def self.stable_failure_validation(record)
    record[:stable_failure] ? nil : "hash-bound owner disposition missing"
  end

  def self.build(root, output, seed:, final_trials:, contracts:, include_stable_failures:)
    self.last_call = {"seed" => seed, "final_trials" => File.readlines(final_trials, chomp: true),
                     "contracts" => contracts, "include_stable_failures" => include_stable_failures}
    FileUtils.mkdir_p(output)
    {packet_count: last_call.fetch("final_trials").length, outcome_count: 24, output: output}
  end
end

require_relative "../review_batch"

class ReviewBatchTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("review-batch-test")
    @root = File.join(@tmp, "grid")
    @repo = File.join(@tmp, "source")
    @grid_summary = File.join(@repo, "scripts", "grid_summary.rb")
    @review_packets = File.join(@repo, "scripts", "review_packets.rb")
    @contracts_dir = File.join(@tmp, "inputs")
    @contracts = File.join(@contracts_dir, "contracts.json")
    FileUtils.mkdir_p([@root, File.dirname(@grid_summary), @contracts_dir])
    File.write(@grid_summary, "# stub\n")
    File.write(@review_packets, "# stub\n")
    File.write(@contracts, JSON.generate("notification_digest" => "Neutral contract"))
    @cells = []
    @summaries = []
    @review_records = []
    index = 0
    %w[claude codex].each do |agent|
      %w[natural specified].each do |track|
        %w[baseline ruby-plainspoken rubypowers].each do |condition|
          [1, 2].each do |repeat|
            index += 1
            cell = {"task" => "notification_digest", "agent" => agent, "track" => track,
                    "condition" => condition, "repeat" => repeat}
            @cells << cell
            relative = format("%04d", index)
            FileUtils.mkdir_p(File.join(@root, relative))
            meta = cell.merge("status" => "complete", "checks_passed" => true, "restoration_verified" => true)
            File.write(File.join(@root, relative, "meta.json"), JSON.generate(meta))
            disposition = "complete"
            correctness = true
            stable_failure = false
            if index == 1
              disposition = "task_failure"
              correctness = false
              stable_failure = true
            elsif index == 2
              disposition = "task_failure"
              correctness = false
              stable_failure = true
              File.write(File.join(@root, relative, "meta.json"), JSON.generate(meta.merge("status" => "awaiting_review", "checks_passed" => false)))
            end
            @summaries << {"grid_index" => index, "cell" => cell, "disposition" => disposition,
                           "correctness" => correctness, "final_path" => relative}
            @review_records << {"relative" => relative, "validation" => stable_failure ? "status is not complete" : nil,
                                "stable_failure" => stable_failure}
          end
        end
      end
    end
    write(File.join(@root, "grid.json"), {"cells" => @cells})
    write(File.join(@root, "summary.json"), {"cells" => @summaries})
    write(File.join(@root, "review-records.json"), @review_records)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_track_batch_includes_stable_failure_and_excludes_operator_error
    write(File.join(@root, "0001", "protocol-deviation.json"), {
      "classification" => "operator_protocol_error", "eligible_behavioral_trial" => false
    })
    result = build(track: "natural", stage: "stage1")

    assert_equal 24, result.fetch("assigned_task_cells_before_track_filter")
    assert_equal 12, result.fetch("assigned_track_cells")
    assert_equal 11, result.fetch("selected_final_trials")
    assert_equal 1, result.fetch("excluded_track_cells")
    assert_equal 11, result.fetch("actual_packet_count")
    assert_equal true, ReviewPackets.last_call.fetch("include_stable_failures")
    assert_includes ReviewPackets.last_call.fetch("final_trials"), "0002"
    refute_includes ReviewPackets.last_call.fetch("final_trials"), "0001"
    assert_includes File.read(File.join(result.fetch("output"), "owner-notes.md")), "operator protocol deviation"
  end

  def test_explicit_blocked_cell_counts_terminal_but_is_excluded
    blocked_index = 1
    FileUtils.rm_f(File.join(@root, format("%04d", blocked_index), "meta.json"))
    @summaries[blocked_index - 1]["disposition"] = "unstarted"
    write(File.join(@root, "summary.json"), {"cells" => @summaries})
    write(File.join(@root, "stage2-blocked", "0001.json"), {
      "grid_index" => blocked_index, "cell" => @cells.fetch(blocked_index - 1), "status" => "blocked", "reason" => "invalid source"
    })

    result = build(track: "natural", stage: "stage2")

    assert_equal 11, result.fetch("selected_final_trials")
    assert_equal 1, result.fetch("active_blocked_cells_in_task")
    assert_includes File.read(File.join(result.fetch("output"), "owner-notes.md")), "explicitly blocked: invalid source"
  end

  def test_unresolved_cell_in_other_track_refuses_before_track_filter
    @summaries[12]["disposition"] = "awaiting_review"
    write(File.join(@root, "summary.json"), {"cells" => @summaries})

    error = assert_raises(RuntimeError) { build(track: "natural", stage: "stage1") }

    assert_match(/before track filtering/, error.message)
    refute File.exist?(File.join(@tmp, "out"))
  end

  def test_stage2_excludes_completed_cell_paired_to_operator_deviation_source
    source = File.join(@tmp, "stage1", "0001")
    FileUtils.mkdir_p(source)
    write(File.join(source, "protocol-deviation.json"), {"eligible_behavioral_trial" => false})
    write(File.join(@root, "0001", "meta.json"), @cells.first.merge("stage1_source_trial" => source))

    result = build(track: "natural", stage: "stage2")

    assert_equal 11, result.fetch("selected_final_trials")
    assert_match(/stage-1 source is an operator protocol deviation/, result.fetch("exclusions").first.fetch("reason"))
  end

  def test_output_inside_contract_inputs_is_refused
    output = File.join(@contracts_dir, "report")
    assert ContrastReviewBatch.within?(output, @contracts_dir)

    error = assert_raises(RuntimeError) do
      ContrastReviewBatch.build(grid_root: @root, stage: "stage1", task: "notification_digest", track: "natural",
                                contracts: @contracts, output: output, grid_summary_path: @grid_summary,
                                review_packets_path: @review_packets)
    end

    assert_match(/outside grid, contract, and source inputs/, error.message)
    refute File.exist?(output)
  end

  def test_output_inside_source_tree_is_refused
    output = File.join(@repo, "report")

    error = assert_raises(RuntimeError) do
      ContrastReviewBatch.build(grid_root: @root, stage: "stage1", task: "notification_digest", track: "natural",
                                contracts: @contracts, output: output, grid_summary_path: @grid_summary,
                                review_packets_path: @review_packets)
    end

    assert_match(/inside project must be under reports/, error.message)
  end

  def test_realistic_project_reports_output_is_allowed
    contracts_dir = File.join(@repo, "contrast-v2", "reportingcontracts")
    output = File.join(@repo, "reports", "newbatch")
    FileUtils.mkdir_p([contracts_dir, File.dirname(output)])
    contracts = File.join(contracts_dir, "natural.json")
    File.write(contracts, JSON.generate("notification_digest" => "Neutral contract"))

    result = ContrastReviewBatch.build(grid_root: @root, stage: "stage1", task: "notification_digest", track: "natural",
                                      contracts: contracts, output: output, grid_summary_path: @grid_summary,
                                      review_packets_path: @review_packets)

    assert_equal 12, result.fetch("actual_packet_count")
    assert File.file?(File.join(output, "batch-summary.json"))
  end

  private

  def build(track:, stage:)
    output = File.join(@tmp, "out")
    ContrastReviewBatch.build(grid_root: @root, stage: stage, task: "notification_digest", track: track,
                              contracts: @contracts, output: output, grid_summary_path: @grid_summary,
                              review_packets_path: @review_packets)
  end

  def write(path, object)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(object))
  end
end
