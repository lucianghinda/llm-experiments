#!/usr/bin/env ruby
# Dry-run-first, sequential trial runner. Ruby standard library only.
require "digest"
require "base64"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "securerandom"
require "shellwords"

class TrialHarness
  DEFAULT_SEED = 20_261_030
  MIN_FREE_BYTES = 4 * 1024 * 1024 * 1024
  DEFAULT_TIMEOUT = 20 * 60
  PILOT_IMAGE_DIGEST = "sha256:2f81affa534cf256462a9d175b44edc4d1430bbb99d296ad7483081c60000140"

  def initialize(options)
    @options = options
    @root = File.expand_path(__dir__)
    @workspace = File.join(@root, "model_workspace")
    @results = File.expand_path(options.fetch(:results))
    @models = options.fetch(:models)
    @image = options.fetch(:image)
    @seed = options.fetch(:seed)
    @tools_dir = options[:tools_dir] && File.expand_path(options[:tools_dir])
    @auth_home = options[:auth_home] && File.expand_path(options[:auth_home])
  end

  def plan
    validate_models!
    cells = @models.flat_map { |model| 1.upto(3).map { |repeat| [model, repeat] } }
    random = Random.new(@seed)
    cells.shuffle(random: random).map do |model, repeat|
      { "blind_id" => SecureRandom.hex(8), "model" => model, "repeat" => repeat }
    end
  end

  def run
    cells = plan
    if @options.fetch(:dry_run)
      puts JSON.pretty_generate(dry_run_report(cells))
      return 0
    end

    preflight!(cells)
    execute_sequentially(cells)
    0
  rescue StandardError => error
    warn "BLOCKED: #{error.class}: #{error.message}"
    2
  end

  private

  def validate_models!
    raise "provide exactly four distinct model IDs with --models a,b,c,d" unless @models&.length == 4 && @models.uniq.length == 4
    raise "model IDs must not contain whitespace" if @models.any? { |model| model.match?(/\s/) }
  end

  def dry_run_report(cells)
    {
      "mode" => "dry_run_only_no_model_calls",
      "seed" => @seed,
      "cell_count" => cells.length,
      "sequential" => true,
      "mount_source" => @workspace,
      "evaluator_mount" => false,
      "image" => @image,
      "cells" => cells.map { |cell| cell.reject { |key, _| key == "model" }.merge("model" => "BLINDED") }
    }
  end

  def preflight!(cells)
    raise "model workspace missing" unless File.directory?(@workspace)
    raise "model workspace must not contain evaluator/" if File.exist?(File.join(@workspace, "evaluator"))
    raise "disk gate failed: fewer than 4 GiB free" if free_bytes < MIN_FREE_BYTES
    raise "Apple container system unavailable" unless container_system_ready?
    digest, image_json = inspect_image
    expected_digest = @options.fetch(:expected_image_digest)
    unless digest == expected_digest
      raise "container image digest mismatch: expected #{expected_digest}, inspected #{@inspected_digests.inspect}"
    end
    tools_dir = File.expand_path(@options.fetch(:tools_dir))
    codex_bin = File.join(tools_dir, "node_modules", ".bin", "codex")
    raise "--tools-dir must contain node_modules/.bin/codex" unless File.file?(codex_bin)
    cli_version_out, _err, cli_status = Open3.capture3(*build_version_command(tools_dir))
    raise "cannot read Codex CLI version" unless cli_status.success?
    cli_version = cli_version_out.strip
    expected = @options.fetch(:expected_cli_version)
    raise "CLI version mismatch: expected #{expected}, got #{cli_version}" unless cli_version.include?(expected)
    auth_home = File.expand_path(@options.fetch(:auth_home))
    raise "subscription auth home is missing" unless File.directory?(auth_home)
    auth_status = subscription_status(auth_home, tools_dir)
    raise "login is not a ChatGPT subscription login" unless auth_status.match?(/Logged in using ChatGPT/i)
    raise "login appears to use an API key" if auth_status.match?(/API key/i)
    @image_digest = digest
    @image_inspect_sha256 = Digest::SHA256.hexdigest(image_json)
    @cli_version = cli_version
    @auth_home = auth_home
    @tools_dir = tools_dir
    @plan = cells
  end

  def execute_sequentially(cells)
    FileUtils.mkdir_p(@results)
    mapping = {}
    manifest = {
      "seed" => @seed, "image" => @image, "image_digest" => @image_digest,
      "image_inspect_sha256" => @image_inspect_sha256,
      "cli_version" => @cli_version, "sequential" => true,
      "workspace_sha256" => tree_digest(@workspace), "cells" => []
    }

    FileUtils.mkdir_p(@results)

    cells.each_with_index do |cell, index|
      check_disk_space!
      blind_id = cell.fetch("blind_id")
      model = cell.fetch("model")
      trial_dir = File.join(@results, blind_id)
      raise "result path already exists: #{blind_id}" if File.exist?(trial_dir)
      FileUtils.mkdir_p(trial_dir)
      trial_workspace = File.join(trial_dir, "workspace")
      FileUtils.cp_r(@workspace, trial_workspace)
      mapping[blind_id] = { "model" => model, "repeat" => cell.fetch("repeat") }
      write_json(File.join(@results, "unblinding_key.json"), mapping)
      record = execute_one(model, blind_id, trial_dir, trial_workspace)
      record["sequence"] = index + 1
      manifest["cells"] << record
      write_json(File.join(@results, "manifest.json"), manifest)
    end

    write_json(File.join(@results, "unblinding_key.json"), mapping)
  end

  def execute_one(model, blind_id, trial_dir, trial_workspace)
    prompt = File.read(File.join(trial_workspace, "PROMPT.md"))
    prompt = "#{prompt}\n\nModel-visible source files are in the current workspace. Read them before answering."
    last_message = File.join(trial_dir, "response.md")
    container_name = "payment-investigation-#{blind_id}"
    FileUtils.cp(File.join(@root, "auth_runner.rb"), File.join(trial_dir, "auth_runner.rb"))
    cmd = build_trial_command(model, trial_workspace, trial_dir, container_name)
    write_text(File.join(trial_dir, "prompt.md"), prompt)
    exit_status = nil
    event_text = ""
    stderr_text = ""
    Open3.popen3(*cmd, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      out_reader = Thread.new { stdout.read }
      err_reader = Thread.new { stderr.read }
      stdin.write(prompt)
      stdin.close
      unless wait_thr.join(@options.fetch(:timeout) + 60)
        Process.kill("TERM", -wait_thr.pid) rescue nil
        Open3.capture3("container", "kill", container_name) rescue nil
        wait_thr.join(3) || (Process.kill("KILL", -wait_thr.pid) rescue nil)
        File.write(File.join(trial_dir, "timeout.txt"), "Timed out after #{@options.fetch(:timeout)} seconds\n")
        raise "trial #{blind_id} exceeded timeout"
      end
      out_reader.join
      err_reader.join
      event_text = out_reader.value
      stderr_text = err_reader.value
      exit_status = wait_thr.value.exitstatus
    end
    completed_turns = extract_completed_turns(event_text)
    raw_response = extract_response(event_text)
    unless exit_status == 0 && completed_turns.positive? && !raw_response.strip.empty?
      write_json(File.join(trial_dir, "invalid_run.json"), {
        "blind_id" => blind_id, "exit_status" => exit_status,
        "completed_turns" => completed_turns, "answer_present" => !raw_response.strip.empty?,
        "stderr_sha256" => Digest::SHA256.hexdigest(stderr_text)
      })
      raise "invalid trial #{blind_id}: exit=#{exit_status.inspect}, completed_turns=#{completed_turns}, answer_present=#{!raw_response.strip.empty?}"
    end
    raw_response_sha256 = Digest::SHA256.hexdigest(raw_response)
    write_text(last_message, raw_response)
    write_blind_response(blind_id, redact_model_labels(raw_response, model))
    usage = extract_usage(event_text)
    write_json(File.join(trial_dir, "usage.json"), usage)
    write_json(File.join(trial_dir, "run_meta.json"), {
      "blind_id" => blind_id, "exit_status" => exit_status,
      "stderr_sha256" => Digest::SHA256.hexdigest(stderr_text),
      "raw_response_sha256" => raw_response_sha256, "timed_out" => false
    })
    {
      "blind_id" => blind_id, "exit_status" => exit_status, "usage" => usage,
      "completed_turns" => completed_turns,
      "raw_response_sha256" => raw_response_sha256
    }
  end

  def extract_usage(jsonl)
    total = { "input_tokens" => 0, "cached_input_tokens" => 0, "output_tokens" => 0 }
    jsonl.each_line do |line|
      event = JSON.parse(line) rescue next
      next unless event["type"] == "turn.completed"
      usage = event["usage"]
      next unless usage.is_a?(Hash)
      total["input_tokens"] += usage["input_tokens"].to_i
      total["cached_input_tokens"] += usage["cached_input_tokens"].to_i
      total["output_tokens"] += usage["output_tokens"].to_i
    end
    total
  end

  def extract_completed_turns(jsonl)
    count = 0
    jsonl.each_line do |line|
      event = JSON.parse(line)
      count += 1 if event["type"] == "turn.completed"
    rescue JSON::ParserError
      next
    end
    count
  end

  def extract_response(jsonl)
    messages = jsonl.each_line.filter_map do |line|
      event = JSON.parse(line) rescue next
      item = event["item"] || event.dig("payload", "item")
      item["text"] if item.is_a?(Hash) && item["type"] == "agent_message"
    end
    messages.last.to_s
  end

  def container_system_ready?
    out, _err, status = Open3.capture3("container", "system", "status")
    status.success? && out.include?("apiserver is running")
  rescue Errno::ENOENT
    false
  end

  def inspect_image
    out, err, status = Open3.capture3(*build_image_inspect_command)
    raise "container image inspect failed: #{err.strip}" unless status.success?
    json = JSON.parse(out)
    expected = @options.fetch(:expected_image_digest)
    @inspected_digests = find_digests(json).uniq
    [@inspected_digests.find { |digest| digest == expected }, out]
  rescue JSON::ParserError => error
    raise "container image inspect returned invalid JSON: #{error.message}"
  end

  def find_digests(value)
    case value
    when Hash then value.values.flat_map { |child| find_digests(child) }
    when Array then value.flat_map { |child| find_digests(child) }
    when String then value.scan(/sha256:[0-9a-f]{64}/)
    else []
    end
  end

  def build_image_inspect_command
    ["container", "image", "inspect", @image]
  end

  def build_version_command(tools_dir)
    ["container", "run", "--rm", "--volume", "#{tools_dir}:/tools", @image,
     "bash", "-lc", "/tools/node_modules/.bin/codex --version"]
  end

  def build_trial_command(model, workspace, results, container_name = "payment-investigation-trial")
    [@options.fetch(:container_bin, "container"), "run", "--rm", "-i", "--name", container_name, "--memory", "4g", "--cpus", "2",
     "--volume", "#{workspace}:/workspace",
     "--volume", "#{results}:/results",
     "--volume", "#{@tools_dir}:/tools",
     "--volume", "#{@auth_home}:/home/agent/.agent-auth",
     "--workdir", "/workspace", @image, "bash", "-lc",
     "exec ruby /results/auth_runner.rb /home/agent/.agent-auth/codex /home/agent/.codex-trial /tools/node_modules/.bin/codex exec --json --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --ignore-user-config --ephemeral -C /workspace --model #{Shellwords.escape(model)} -"]
  end

  def redact_model_labels(text, model)
    (@models + [model]).uniq.sort_by { |label| -label.length }.reduce(text) do |content, label|
      content.gsub(/(?<![A-Za-z0-9_-])#{Regexp.escape(label)}(?![A-Za-z0-9_-])/i, "[MODEL]")
    end
  end

  def write_blind_response(blind_id, response)
    blind_dir = File.join(@results, "blind_outputs")
    FileUtils.mkdir_p(blind_dir)
    path = File.join(blind_dir, "#{blind_id}.md")
    write_text(path, response)
    path
  end

  def check_disk_space!
    raise "disk gate failed during trial grid: fewer than 4 GiB free" if free_bytes < MIN_FREE_BYTES
  end

  def subscription_status(auth_home, tools_dir)
    cmd = ["container", "run", "--rm", "--volume", "#{tools_dir}:/tools",
           "--volume", "#{auth_home}:/home/agent/.agent-auth",
           "--env", "CODEX_HOME=/home/agent/.agent-auth/codex", @image,
           "bash", "-lc", "/tools/node_modules/.bin/codex login status 2>&1"]
    out, err, status = Open3.capture3(*cmd)
    raise "container login status preflight failed: #{err.strip}" unless status.success?
    out
  end

  def free_bytes
    probe = @results
    probe = File.dirname(probe) until File.exist?(probe)
    out, _err, status = Open3.capture3("df", "-Pk", probe)
    raise "cannot check free disk space" unless status.success?
    out.lines.last.split[3].to_i * 1024
  end

  def tree_digest(path)
    entries = Dir.glob("**/*", File::FNM_DOTMATCH, base: path).select { |entry| File.file?(File.join(path, entry)) }.sort
    digest = Digest::SHA256.new
    entries.each do |entry|
      digest << entry << "\0" << Digest::SHA256.file(File.join(path, entry)).hexdigest << "\n"
    end
    digest.hexdigest
  end

  def write_json(path, value)
    File.write(path, JSON.pretty_generate(value) + "\n", mode: "w", perm: 0o600)
  end

  def write_text(path, value)
    File.write(path, value, mode: "w", perm: 0o600)
  end
end

options = {
  dry_run: true, seed: TrialHarness::DEFAULT_SEED, results: File.join(__dir__, "results"),
  image: "llmx-app-campfire:latest", timeout: TrialHarness::DEFAULT_TIMEOUT,
  expected_cli_version: "0.164.0", expected_image_digest: TrialHarness::PILOT_IMAGE_DIGEST, tools_dir: nil,
  auth_home: File.expand_path("~/.llmx/auth"), models: nil
}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby run_trials.rb [options]"
  parser.on("--models a,b,c,d", Array, "Four model IDs in a fixed hidden mapping") { |value| options[:models] = value }
  parser.on("--results DIR", "Directory for blinded trial outputs") { |value| options[:results] = value }
  parser.on("--image NAME", "Pinned local container image") { |value| options[:image] = value }
  parser.on("--seed N", Integer, "Shuffle seed (default #{TrialHarness::DEFAULT_SEED})") { |value| options[:seed] = value }
  parser.on("--timeout SECONDS", Integer, "Per-trial timeout") { |value| options[:timeout] = value }
  parser.on("--expected-cli-version VERSION", "Required container Codex CLI version") { |value| options[:expected_cli_version] = value }
  parser.on("--expected-image-digest DIGEST", "Required image digest (default pinned pilot digest)") { |value| options[:expected_image_digest] = value }
  parser.on("--tools-dir DIR", "Host tools volume containing node_modules/.bin/codex") { |value| options[:tools_dir] = value }
  parser.on("--auth-home DIR", "Codex subscription login directory mounted for token refresh") { |value| options[:auth_home] = value }
  parser.on("--dry-run", "Print the blinded 12-cell plan; never make model calls") { options[:dry_run] = true }
  parser.on("--execute", "Run trials after all preflight gates pass") { options[:dry_run] = false }
  parser.on("-h", "--help") { puts parser; exit }
end.parse!

if $PROGRAM_NAME == __FILE__
  options[:tools_dir] ||= ENV["LLMX_CODEX_TOOLS_DIR"]
  options[:models] ||= ENV["LLMX_INVESTIGATION_MODELS"]&.split(",")
  if !options[:dry_run] && options[:tools_dir].to_s.empty?
    warn "BLOCKED: --tools-dir is required for execution"
    exit 2
  end
  exit TrialHarness.new(options).run
end
