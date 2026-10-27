# frozen_string_literal: true

require "open3"
require "tempfile"
require "json"
require "fileutils"
require "rbconfig"
require_relative "pilot"

class PilotChecks
  def initialize
    @count = 0
    @tasks = ModelRoutingPilot.read_tasks
  end

  def assert(value, message = "assertion failed")
    raise message unless value
  end

  def equal(expected, actual, message = nil)
    assert(expected == actual, message || "expected #{expected.inspect}, got #{actual.inspect}")
  end

  def raises(klass)
    begin
      yield
    rescue klass => error
      return error
    end
    raise "expected #{klass}"
  end

  def test_plan_is_exactly_four_by_four_and_labels_actual_task_types
    plan = ModelRoutingPilot.plan(seed: 7, tasks: @tasks)
    equal(16, plan.length)
    equal(16, plan.map { |cell| [cell.fetch("task"), cell.fetch("model")] }.uniq.length)
    equal((1..16).to_a, plan.map { |cell| cell.fetch("sequence") })
    equal("locate / read-only", plan.find { |cell| cell.fetch("task") == "locate-direct-type" }.fetch("task_label"))
    assert(plan.find { |cell| cell.fetch("task") == "feature-room-topic" }.fetch("task_label").include?("mutating"))
    assert(plan.find { |cell| cell.fetch("task") == "test-direct-type" }.fetch("task_label").include?("mutating"))
  end

  def test_seed_reproduces_order
    a = ModelRoutingPilot.plan(seed: 19, tasks: @tasks).map { |cell| [cell["task"], cell["model"]] }
    b = ModelRoutingPilot.plan(seed: 19, tasks: @tasks).map { |cell| [cell["task"], cell["model"]] }
    c = ModelRoutingPilot.plan(seed: 20, tasks: @tasks).map { |cell| [cell["task"], cell["model"]] }
    equal(a, b)
    assert(a != c, "different seeds should change the order")
  end

  def test_rejects_incomplete_task_or_model_sets
    raises(ModelRoutingPilot::Error) { ModelRoutingPilot.plan(seed: 1, tasks: @tasks.first(3)) }
    raises(ModelRoutingPilot::Error) { ModelRoutingPilot.plan(seed: 1, tasks: @tasks, models: ["one"]) }
  end

  def test_rejects_missing_read_only_metadata
    source = File.read(File.join(ModelRoutingPilot::EXPERIMENT, "tasks.yml"))
    source.sub!("    read_only: true\n", "")
    Tempfile.create(["tasks", ".yml"]) do |file|
      file.write(source)
      file.flush
      raises(ModelRoutingPilot::Error) { ModelRoutingPilot.read_tasks(file.path) }
    end
  end

  def test_run_requires_subscription_auth_and_tools_path
    raises(ModelRoutingPilot::Error) { ModelRoutingPilot.parse_options(["--run"]) }
    raises(ModelRoutingPilot::Error) { ModelRoutingPilot.parse_options(["--run", "--auth=subscription"]) }
    options = ModelRoutingPilot.parse_options(["--run", "--auth=subscription", "--tools-dir", "/some/tools"])
    equal(true, options[:run])
    equal("subscription", options[:auth])
    equal("/some/tools", options[:tools_dir])
    equal(false, ModelRoutingPilot.parse_options(["--dry-run"])[ :run ])
    raises(ModelRoutingPilot::Error) do
      ModelRoutingPilot.parse_options(["--run", "--auth=subscription", "--tools-dir", "/some/tools", "--dry-run"])
    end
  end

  def test_api_equivalent_estimate_is_distinct_from_subscription_usage
    usage = { "input_tokens" => 100_000, "cached_input_tokens" => 50_000, "output_tokens" => 10_000 }
    no_rates = ModelRoutingPilot.api_equivalent(usage, nil)
    equal(nil, no_rates.fetch("estimated_usd"))
    priced = ModelRoutingPilot.api_equivalent(usage, {
      "input_per_million" => 1.0,
      "cached_input_per_million" => 0.5,
      "output_per_million" => 2.0,
      "source" => "test fixture",
      "as_of" => "2026-10-27"
    })
    assert((priced.fetch("estimated_usd") - 0.095).abs < 0.000001)
    equal("rates not supplied", no_rates.fetch("reason"))
  end

  def test_transcript_usage_counts_completed_turns_and_cached_subset
    Tempfile.create(["transcript", ".jsonl"]) do |file|
      file.write(JSON.generate("type" => "turn.completed", "usage" => {
        "input_tokens" => 80, "output_tokens" => 12, "cached_input_tokens" => 30,
        "reasoning_output_tokens" => 4
      }) + "\n")
      file.write(JSON.generate("type" => "item.completed") + "\n")
      file.flush
      usage = ModelRoutingPilot.usage_from(file.path)
      equal(1, usage.fetch("turns"))
      equal(80, usage.fetch("input_tokens"))
      equal(30, usage.fetch("cached_input_tokens"))
      equal(12, usage.fetch("output_tokens"))
    end
  end

  def test_isolated_runner_mount_path_is_configurable
    source = File.read(File.join(__dir__, "scripts", "run_trial.rb"))
    assert(!source.include?("/tmp/model-routing-codex"), "found hardcoded temporary tools path")
    assert(source.include?('"#{tools_dir}:/tools"'))
    assert(source.include?("ModelRoutingPreflight.codex_chatgpt_login_error(status, command_success: status_ok)"))
    assert(!source.include?('status.include?("Not logged in")'), "found permissive status-substring check")
    assert(source.include?("ModelRoutingPreflight.disk_error(Kit.free_gb)"))
  end

  def test_codex_preflight_requires_successful_positive_chatgpt_login_signal
    equal(nil, ModelRoutingPreflight.codex_chatgpt_login_error("Logged in using ChatGPT\n", command_success: true))
    assert(ModelRoutingPreflight.codex_chatgpt_login_error("Logged in using ChatGPT\n", command_success: false))
    assert(ModelRoutingPreflight.codex_chatgpt_login_error("API key configured - [redacted]\n", command_success: true))
    assert(ModelRoutingPreflight.codex_chatgpt_login_error("Not logged in\n", command_success: true))
    assert(ModelRoutingPreflight.codex_chatgpt_login_error("", command_success: true))
  end

  def test_disk_gate_requires_four_gib_free
    equal(true, ModelRoutingPilot.disk_preflight!(free_gb: 4))
    error = raises(ModelRoutingPilot::Error) { ModelRoutingPilot.disk_preflight!(free_gb: 3) }
    assert(error.message.include?("at least 4 GiB"))
    assert(ModelRoutingPreflight.disk_error(3.9))
    equal(nil, ModelRoutingPreflight.disk_error(4))
    pilot = File.read(File.join(__dir__, "pilot.rb"))
    assert(pilot.include?("disk_preflight!"), "pilot must gate each planned cell")
  end

  def test_dry_run_does_not_mutate_pilot_tree
    before = Dir.glob(File.join(__dir__, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "--disable-gems", File.join(__dir__, "pilot.rb"), "--dry-run", "--seed", "42")
    after = Dir.glob(File.join(__dir__, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort
    assert(status.success?, stderr)
    assert(stdout.include?("16 trials"))
    assert(stdout.include?("Dry run only"))
    equal(before, after)
  end

  def test_prepare_copies_prompts_and_writes_planned_status
    plan = ModelRoutingPilot.plan(seed: 29, tasks: @tasks)
    before = Dir.glob(File.join(__dir__, "plans", "*"))
    created = []
    begin
      ModelRoutingPilot.prepare_plan(plan, seed: 29)
      created = Dir.glob(File.join(__dir__, "plans", "*")) - before
      equal(1, created.length)
      manifest = JSON.parse(File.read(File.join(created.first, "status.json")))
      equal("planned", manifest.fetch("status"))
      equal(16, manifest.fetch("planned_trials"))
      equal(4, Dir.glob(File.join(created.first, "prompts", "*.txt")).length)
    ensure
      FileUtils.rm_rf(created)
    end
  end

  def run
    methods = self.class.instance_methods(false).grep(/\Atest_/).sort
    methods.each do |name|
      public_send(name)
      @count += 1
      puts "PASS #{name}"
    end
    puts "#{@count} checks passed"
  end
end

PilotChecks.new.run if $PROGRAM_NAME == __FILE__
