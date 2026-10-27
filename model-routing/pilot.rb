#!/usr/bin/env ruby
# frozen_string_literal: true

# Small, sequential pilot for the four existing convention-navigation tasks.
# Nothing runs by default. Live cells require an explicit subscription-auth
# request and a successful positive login preflight; each cell also requires at
# least 4 GiB of free disk immediately before launch.
#
#   ruby model-routing/pilot.rb --dry-run --seed 20261027
#   ruby model-routing/pilot.rb --run --auth=subscription --tools-dir "$CODEX_TOOLS_DIR"

require "optparse"
require "fileutils"
require "json"
require "time"
require "open3"
require "rbconfig"
require_relative "../containers/scripts/lib/kit"
require_relative "scripts/preflight"

module ModelRoutingPilot
  ROOT = File.expand_path("..", __dir__)
  EXPERIMENT = File.join(ROOT, "convention-navigation")
  TRIAL_SCRIPT = File.join(__dir__, "scripts", "run_trial.rb")
  RUNNER_SCRIPT = File.join(__dir__, "scripts", "runner.rb")
  TASK_IDS = %w[
    locate-direct-type
    locate-generated-secret
    feature-room-topic
    test-direct-type
  ].freeze
  MODELS = %w[gpt-6-luna gpt-6.1-terra gpt-6.1-sol gpt-6-astra].freeze
  AGENT = "codex"
  CONDITION = "conventional"
  LABELS = {
    "locate-direct-type" => "locate / read-only",
    "locate-generated-secret" => "locate / read-only",
    "feature-room-topic" => "cross-layer feature / mutating task",
    "test-direct-type" => "test addition / mutating task"
  }.freeze
  FAMILIES = {
    "locate-direct-type" => "locate",
    "locate-generated-secret" => "locate",
    "feature-room-topic" => "cross-layer",
    "test-direct-type" => "test"
  }.freeze
  READ_ONLY = {
    "locate-direct-type" => true,
    "locate-generated-secret" => true,
    "feature-room-topic" => false,
    "test-direct-type" => false
  }.freeze

  class Error < StandardError; end

  # Parse the deliberately small tasks.yml subset used here without depending
  # on the harness loader. Task identity and family labels are checked against
  # this allowlist; arbitrary task files cannot enter the pilot accidentally.
  def self.read_tasks(path = File.join(EXPERIMENT, "tasks.yml"))
    text = File.read(path)
    rows = text.scan(/^  - id: ([a-z0-9-]+)\n(.*?)(?=^  - id:|\z)/m).to_h do |id, body|
      family = body[/^    family: ([a-z-]+)$/, 1]
      read_only = body[/^    read_only: (true|false)$/, 1]
      prompt = body[/^    prompt: ([a-z0-9-]+\.txt)$/, 1]
      [id, { "family" => family, "read_only_raw" => read_only, "prompt" => prompt }]
    end

    missing = TASK_IDS - rows.keys
    raise Error, "tasks.yml is missing required tasks: #{missing.join(', ')}" unless missing.empty?

    TASK_IDS.map do |id|
      row = rows.fetch(id)
      if row["family"].nil? || row["read_only_raw"].nil? || row["prompt"].nil?
        raise Error, "task #{id} has no family/read_only/prompt metadata"
      end
      unless row["family"] == FAMILIES.fetch(id) && (row["read_only_raw"] == "true") == READ_ONLY.fetch(id)
        raise Error, "task #{id} family/read_only metadata differs from the pilot's reviewed task definition"
      end

      row.merge("read_only" => row.delete("read_only_raw") == "true", "id" => id, "label" => LABELS.fetch(id))
    end
  end

  def self.plan(seed:, tasks: read_tasks, models: MODELS)
    raise Error, "pilot requires exactly four allowlisted tasks" unless tasks.map { |t| t.fetch("id") }.sort == TASK_IDS.sort
    raise Error, "pilot requires the four pinned models" unless models == MODELS

    cells = tasks.product(models).map do |task, model|
      {
        "task" => task.fetch("id"),
        "task_label" => task.fetch("label"),
        "family" => task.fetch("family"),
        "read_only" => task.fetch("read_only"),
        "model" => model,
        "agent" => AGENT,
        "condition" => CONDITION
      }
    end
    cells.shuffle(random: Random.new(seed)).each_with_index.map do |cell, index|
      cell.merge("sequence" => index + 1)
    end
  end

  def self.parse_options(argv)
    options = { run: false, prepare: false, dry_run: false, auth: nil, tools_dir: nil, api_rates: nil, seed: 20_261_027 }
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby model-routing/pilot.rb [--dry-run | --prepare-plan | --run --auth=subscription --tools-dir PATH] [--seed N]"
      opts.on("--dry-run", "Print the complete plan without writing files or running trials") { options[:dry_run] = true }
      opts.on("--run", "Execute all 16 trials sequentially (requires --auth=subscription)") { options[:run] = true }
      opts.on("--auth MODE", "Required with --run; currently accepts subscription") { |mode| options[:auth] = mode }
      opts.on("--tools-dir PATH", "Codex installation directory mounted read-only at /tools") { |path| options[:tools_dir] = path }
      opts.on("--api-rates PATH", "Optional JSON rates for API-equivalent estimates; never a spend cap") { |path| options[:api_rates] = path }
      opts.on("--prepare-plan", "Copy prompts and plan metadata into a local planned run folder; never executes") { options[:prepare] = true }
      opts.on("--seed N", Integer, "Seed for reproducible randomized order") { |n| options[:seed] = n }
      opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
    end
    parser.parse!(argv)
    raise Error, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
    raise Error, "--run requires --auth=subscription" if options[:run] && options[:auth] != "subscription"
    raise Error, "--auth is only supported with --run and must be subscription" if options[:auth] && options[:auth] != "subscription"
    raise Error, "--tools-dir is required with --run" if options[:run] && options[:tools_dir].to_s.empty?
    raise Error, "--tools-dir is only supported with --run" if options[:tools_dir] && !options[:run]
    raise Error, "--api-rates is only supported with --run" if options[:api_rates] && !options[:run]
    raise Error, "choose only one of --dry-run, --prepare-plan, or --run" if [options[:run], options[:prepare], options[:dry_run]].count(true) > 1
    options
  end

  def self.print_plan(cells, seed)
    puts "Model routing pilot: #{cells.length} trials; seed=#{seed}; sequential"
    puts "Task types are existing harness tasks; labels indicate their actual mutation behavior."
    cells.each do |cell|
      mode = cell.fetch("read_only") ? "read-only" : "mutating"
      puts format("%2d. %-28s %-34s %-16s [%s]", cell.fetch("sequence"), cell.fetch("task"), cell.fetch("task_label"), cell.fetch("model"), mode)
    end
    puts "Dry run only: no trial or filesystem mutation was performed."
  end

  def self.prepare_plan(cells, seed:)
    tasks = read_tasks
    prompt_sources = tasks.to_h do |task|
      source = File.join(EXPERIMENT, "prompts", "campfire", task.fetch("prompt"))
      raise Error, "missing rendered prompt: #{source}; run render_prompts.rb before preparing" unless File.file?(source)

      [task.fetch("id"), source]
    end
    stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S")
    destination = File.join(__dir__, "plans", "#{stamp}-seed-#{seed}-pid-#{Process.pid}")
    FileUtils.mkdir_p(File.join(destination, "prompts"))
    FileUtils.cp(File.join(EXPERIMENT, "tasks.yml"), File.join(destination, "tasks.yml"))
    prompt_sources.each_value { |source| FileUtils.cp(source, File.join(destination, "prompts", File.basename(source))) }
    manifest = {
      "status" => "planned", "created_at" => Time.now.utc.iso8601,
      "seed" => seed, "planned_trials" => cells.length, "models" => MODELS,
      "agent" => AGENT, "condition" => CONDITION, "tasks" => tasks, "trials" => cells
    }
    File.write(File.join(destination, "status.json"), JSON.pretty_generate(manifest) + "\n")
    puts "Prepared a local plan (no trials run): #{destination}"
  end

  def self.usage_from(transcript)
    return nil unless File.file?(transcript)

    totals = { "input_tokens" => 0, "output_tokens" => 0, "cached_input_tokens" => 0,
               "reasoning_output_tokens" => 0, "turns" => 0 }
    File.foreach(transcript) do |line|
      event = JSON.parse(line) rescue nil
      next unless event && event["type"] == "turn.completed"

      usage = event["usage"] || {}
      totals["turns"] += 1
      totals["input_tokens"] += usage["input_tokens"].to_i
      totals["output_tokens"] += usage["output_tokens"].to_i
      totals["cached_input_tokens"] += usage["cached_input_tokens"].to_i
      totals["reasoning_output_tokens"] += usage["reasoning_output_tokens"].to_i
    end
    totals
  end

  def self.api_equivalent(usage, rates)
    return { "estimated_usd" => nil, "reason" => "rates not supplied" } unless rates
    rates = rates.transform_keys(&:to_s)
    %w[input_per_million cached_input_per_million output_per_million].each do |key|
      return { "estimated_usd" => nil, "reason" => "incomplete or unknown rates" } unless rates[key].is_a?(Numeric) && rates[key] >= 0
    end
    return { "estimated_usd" => nil, "reason" => "rate source and date are required" } unless rates["source"].is_a?(String) && !rates["source"].empty? && rates["as_of"].is_a?(String) && !rates["as_of"].empty?

    uncached = [usage.fetch("input_tokens") - usage.fetch("cached_input_tokens"), 0].max
    amount = (uncached * rates["input_per_million"] +
              usage.fetch("cached_input_tokens") * rates["cached_input_per_million"] +
              usage.fetch("output_tokens") * rates["output_per_million"]) / 1_000_000.0
    { "estimated_usd" => amount.round(6), "basis" => rates }
  end

  def self.disk_preflight!(free_gb: Kit.free_gb)
    message = ModelRoutingPreflight.disk_error(free_gb)
    raise Error, message if message

    true
  end

  def self.summarize_by_model(trials)
    MODELS.to_h do |model|
      runs = trials.select { |trial| trial.fetch("model") == model }
      usages = runs.map { |trial| trial["subscription_usage_tokens"] }.compact
      estimates = runs.map { |trial| trial.dig("api_equivalent_estimate", "estimated_usd") }
      summary = {
        "trials_completed" => runs.count { |trial| trial["status"] == "completed" },
        "trials_with_usage" => usages.length,
        "subscription_usage_tokens" => %w[input_tokens output_tokens cached_input_tokens reasoning_output_tokens].to_h do |key|
          [key, usages.sum { |usage| usage.fetch(key, 0) }]
        end,
        "api_equivalent_estimated_usd" => estimates.all? { |amount| amount.is_a?(Numeric) } ? estimates.sum.round(6) : nil
      }
      [model, summary]
    end
  end

  def self.run(cells, seed:, tools_dir:, auth:, api_rates_path: nil)
    raise Error, "execution requires --auth=subscription" unless auth == "subscription"
    tools_dir = File.expand_path(tools_dir)
    codex = File.join(tools_dir, "node_modules", ".bin", "codex")
    raise Error, "Codex executable missing under --tools-dir: #{codex}" unless File.file?(codex)

    rates = begin
      api_rates_path ? JSON.parse(File.read(api_rates_path)) : nil
    rescue JSON::ParserError => e
      raise Error, "invalid API rate JSON: #{e.message}"
    end
    rates ||= {}
    raise Error, "API rate file must be a JSON object keyed by model" unless rates.is_a?(Hash)
    stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
    output = File.join(__dir__, "runs", "#{stamp}-seed-#{seed}-pid-#{Process.pid}")
    inputs = File.join(output, "inputs")
    FileUtils.mkdir_p(File.join(inputs, "prompts"))
    FileUtils.cp(File.join(EXPERIMENT, "tasks.yml"), File.join(inputs, "tasks.yml"))
    FileUtils.cp(TRIAL_SCRIPT, File.join(inputs, "run_trial.rb"))
    FileUtils.cp(RUNNER_SCRIPT, File.join(inputs, "runner.rb"))
    tasks = read_tasks
    tasks.each do |task|
      source = File.join(EXPERIMENT, "prompts", "campfire", task.fetch("prompt"))
      raise Error, "missing rendered prompt: #{source}" unless File.file?(source)
      FileUtils.cp(source, File.join(inputs, "prompts", File.basename(source)))
    end
    FileUtils.cp(api_rates_path, File.join(inputs, "api-rates.json")) if api_rates_path
    results_root = File.join(output, "results-raw")
    status = {
      "status" => "running", "created_at" => Time.now.utc.iso8601,
      "seed" => seed, "planned_trials" => cells.length, "models" => MODELS,
      "agent" => AGENT, "condition" => CONDITION, "auth_mode" => "subscription",
      "tools_dir" => tools_dir, "usage_source" => "Codex turn.completed transcript events",
      "api_equivalent_estimates" => "Optional estimates from api-rates.json; not actual subscription charges or a hard spending cap",
      "trials" => cells.map { |cell| cell.merge("status" => "pending") },
      "summary_by_model" => {}
    }
    status_path = File.join(output, "status.json")
    write_status(status_path, status)

    cells.each do |cell|
      trial = status["trials"][cell.fetch("sequence") - 1]
      begin
        disk_preflight!
      rescue Error => e
        trial["status"] = "blocked_low_disk"
        trial["failure_reason"] = e.message
        status["status"] = "blocked_low_disk"
        status["stopped_reason"] = e.message
        write_status(status_path, status)
        raise
      end
      trial["status"] = "running"
      trial["started_at"] = Time.now.utc.iso8601
      write_status(status_path, status)
      before = Dir.glob(File.join(results_root, "**", "meta.json"))
      command = [RbConfig.ruby, TRIAL_SCRIPT, "--task", cell.fetch("task"), "--agent", AGENT,
                 "--condition", CONDITION, "--tools-dir", tools_dir, "--results-root", results_root,
                 "--timeout", "600"]
      env = { "LLMX_CODEX_MODEL" => cell.fetch("model"), "LLMX_AUTH_MODE" => auth }
      stdout, stderr, process = Open3.capture3(env, *command, chdir: ROOT)
      trial["exit_status"] = process.exitstatus
      trial["stdout"] = stdout unless stdout.empty?
      trial["stderr"] = stderr unless stderr.empty?
      after = Dir.glob(File.join(results_root, "**", "meta.json")) - before
      if (meta_path = after.first)
        trial["result_path"] = File.dirname(meta_path)
        trial["meta"] = JSON.parse(File.read(meta_path))
        usage = usage_from(File.join(File.dirname(meta_path), "transcript.jsonl"))
        trial["subscription_usage_tokens"] = usage
        trial["api_equivalent_estimate"] = api_equivalent(usage, rates[cell.fetch("model")]) if usage
      end
      trial["status"] = process.success? ? "completed" : "failed"
      trial["finished_at"] = Time.now.utc.iso8601
      status["summary_by_model"] = summarize_by_model(status["trials"])
      write_status(status_path, status)
      unless process.success?
        status["status"] = "failed"
        write_status(status_path, status)
        raise Error, "trial #{cell.fetch('sequence')} failed; later trials stopped. See #{status_path}"
      end
    end
    status["status"] = "completed"
    status["finished_at"] = Time.now.utc.iso8601
    write_status(status_path, status)
    puts "Completed #{cells.length} trials. Status: #{status_path}"
  end

  def self.write_status(path, value)
    temporary = "#{path}.tmp"
    File.write(temporary, JSON.pretty_generate(value) + "\n")
    File.rename(temporary, path)
  end

end

if $PROGRAM_NAME == __FILE__
  begin
    options = ModelRoutingPilot.parse_options(ARGV.dup)
    tasks = ModelRoutingPilot.read_tasks
    plan = ModelRoutingPilot.plan(seed: options[:seed], tasks: tasks)
    if options[:prepare]
      ModelRoutingPilot.prepare_plan(plan, seed: options[:seed])
    elsif options[:run]
      ModelRoutingPilot.run(plan, seed: options[:seed], tools_dir: options[:tools_dir], auth: options[:auth], api_rates_path: options[:api_rates])
    else
      ModelRoutingPilot.print_plan(plan, options[:seed])
    end
  rescue ModelRoutingPilot::Error, Errno::ENOENT => e
    warn "pilot: #{e.message}"
    exit 1
  end
end
