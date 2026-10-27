require "minitest/autorun"
require "rbconfig"
require "tmpdir"
require_relative "run_trials"
require_relative "auth_runner"

class TrialHarnessTest < Minitest::Test
  def base_options(overrides = {})
    {
      dry_run: true, seed: 100, results: "/tmp/results", image: "llmx-app-campfire:latest",
      models: %w[gpt-6.1-sol gpt-6.1-terra gpt-6-luna gpt-6-astra],
      tools_dir: "/tools", auth_home: "/auth", expected_image_digest: TrialHarness::PILOT_IMAGE_DIGEST,
      expected_cli_version: "0.164.0", timeout: 1200
    }.merge(overrides)
  end

  def test_plan_has_twelve_sequential_blinded_cells_with_three_repeats_per_model
    models = %w[model-a model-b model-c model-d]
    options = { dry_run: true, seed: 100, results: "/tmp/results", image: "example", models: models }
    harness = TrialHarness.new(options)
    cells = harness.send(:plan)

    assert_equal 12, cells.length
    assert_equal 12, cells.map { |cell| cell.fetch("blind_id") }.uniq.length
    assert_equal models.sort, cells.group_by { |cell| cell.fetch("model") }.map { |model, _| model }.sort
    assert_equal [3, 3, 3, 3], cells.group_by { |cell| cell.fetch("model") }.values.map(&:length)
  end

  def test_plan_order_is_repeatable_for_a_seed
    options = { dry_run: true, seed: 20261030, results: "/tmp/results", image: "example", models: %w[a b c d] }
    first = TrialHarness.new(options).send(:plan).map { |cell| [cell["model"], cell["repeat"]] }
    second = TrialHarness.new(options).send(:plan).map { |cell| [cell["model"], cell["repeat"]] }
    assert_equal first, second
  end

  def test_token_extractor_keeps_cumulative_maximum_usage
    harness = TrialHarness.allocate
    jsonl = <<~JSON
      {"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":5}}
      {"type":"turn.completed","usage":{"input_tokens":24,"cached_input_tokens":6,"output_tokens":9}}
      {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999,"cached_input_tokens":999,"output_tokens":999}}}}
    JSON
    assert_equal({ "input_tokens" => 34, "cached_input_tokens" => 8, "output_tokens" => 14 }, harness.send(:extract_usage, jsonl))
    assert_equal 2, harness.send(:extract_completed_turns, jsonl)
  end

  def test_trial_executable_uses_apple_container_and_mounts_no_evaluator
    command = TrialHarness.new(base_options(seed: 7))
                           .send(:build_trial_command, "gpt-6.1-sol", "/trial/workspace", "/trial/results", "trial-blind")

    assert_equal ["container", "run"], command.first(2)
    refute_includes command, "docker"
    refute command.any? { |part| part.include?("evaluator") }
    assert_includes command, "/trial/workspace:/workspace"
    assert_includes command, "--name"
    assert_includes command, "-i"
    refute_includes command, "--init"
    assert command.any? { |part| part.include?("/tools/node_modules/.bin/codex exec --json") }
    assert command.any? { |part| part.include?("/results/auth_runner.rb") }
    assert command.any? { |part| part.include?("/home/agent/.codex-trial") }
  end

  def test_cli_version_is_checked_inside_the_pinned_container
    command = TrialHarness.new(base_options)
                       .send(:build_version_command, "/host/tools")
    assert_equal ["container", "run"], command.first(2)
    assert_includes command, "/tools/node_modules/.bin/codex --version"
    refute command.include?("/host/tools/node_modules/.bin/codex")
  end

  def test_image_inspection_uses_apple_container_image_inspect
    harness = TrialHarness.new(base_options)
    command = harness.send(:build_image_inspect_command)
    assert_equal ["container", "image", "inspect", "llmx-app-campfire:latest"], command
    inspected = harness.send(:find_digests, { "variants" => [{ "descriptor" => { "digest" => TrialHarness::PILOT_IMAGE_DIGEST } }] })
    assert_includes inspected, TrialHarness::PILOT_IMAGE_DIGEST
  end

  def test_blinded_output_is_separate_and_scrubs_model_ids
    Dir.mktmpdir("trial-harness-test") do |directory|
      models = %w[gpt-6.1-sol gpt-6.1-terra gpt-6-luna gpt-6-astra]
      harness = TrialHarness.new(base_options(results: directory, models: models))
      response = harness.send(:redact_model_labels, "My model is gpt-6.1-sol. Answer: no duplicate charge.", models.first)
      path = harness.send(:write_blind_response, "blind123", response)

      assert_equal File.join(directory, "blind_outputs", "blind123.md"), path
      assert_equal "My model is [MODEL]. Answer: no duplicate charge.", File.read(path)
      refute File.exist?(File.join(directory, "blind_outputs", "transcript.jsonl"))
    end
  end

  def test_per_cell_disk_gate_refuses_low_free_space
    harness = TrialHarness.new(base_options)
    harness.define_singleton_method(:free_bytes) { TrialHarness::MIN_FREE_BYTES - 1 }
    error = assert_raises(RuntimeError) { harness.send(:check_disk_space!) }
    assert_match(/disk gate failed/, error.message)
  end

  def test_codex_auth_is_seeded_into_fresh_private_home_without_config_state
    Dir.mktmpdir("codex-auth-seed") do |directory|
      shared = File.join(directory, "shared")
      private_home = File.join(directory, "private")
      FileUtils.mkdir_p(shared)
      auth = { "tokens" => { "access_token" => "old-access", "refresh_token" => "old-refresh" } }
      File.write(File.join(shared, "auth.json"), JSON.generate(auth))
      File.write(File.join(shared, "config.toml"), "state = 'should not be copied'\n")

      assert CodexTrialAuth.seed(shared, private_home)
      assert_equal JSON.generate(auth), File.read(File.join(private_home, "auth.json"))
      refute File.exist?(File.join(private_home, "config.toml"))
    end
  end

  def test_rotated_credential_is_persisted_but_blanked_credential_is_not
    Dir.mktmpdir("codex-auth-refresh") do |directory|
      shared = File.join(directory, "shared")
      private_home = File.join(directory, "private")
      FileUtils.mkdir_p(shared)
      FileUtils.mkdir_p(private_home)
      original = { "tokens" => { "access_token" => "old-access", "refresh_token" => "stable-refresh" } }
      rotated = { "tokens" => { "access_token" => "new-access", "refresh_token" => "stable-refresh" } }
      File.write(File.join(shared, "auth.json"), JSON.generate(original))
      File.write(File.join(private_home, "auth.json"), JSON.generate(rotated))

      assert CodexTrialAuth.persist(shared, private_home)
      assert_equal JSON.generate(rotated), File.read(File.join(shared, "auth.json"))

      blanked = { "tokens" => { "access_token" => "", "refresh_token" => "stable-refresh" } }
      File.write(File.join(private_home, "auth.json"), JSON.generate(blanked))
      error = assert_raises(RuntimeError) { CodexTrialAuth.persist(shared, private_home) }
      assert_match(/blanked/, error.message)
      assert_equal JSON.generate(rotated), File.read(File.join(shared, "auth.json"))
    end
  end

  def test_auth_downgrade_guard_rejects_missing_nil_non_string_and_empty_credentials
    original = { "tokens" => { "access_token" => "old-access", "refresh_token" => "old-refresh" } }
    candidates = [
      { "tokens" => { "refresh_token" => "old-refresh" } },
      { "tokens" => { "access_token" => nil, "refresh_token" => "old-refresh" } },
      { "tokens" => { "access_token" => 7, "refresh_token" => "old-refresh" } },
      { "tokens" => { "access_token" => "", "refresh_token" => "old-refresh" } }
    ]

    candidates.each do |candidate|
      assert CodexTrialAuth.downgrade?(JSON.generate(original), JSON.generate(candidate))
    end
  end

  def test_execute_one_with_fake_container_writes_only_blinded_answer_and_summed_usage
    Dir.mktmpdir("fake-container-trial") do |directory|
      workspace = File.join(directory, "workspace")
      trial_dir = File.join(directory, "trial")
      FileUtils.mkdir_p(workspace)
      FileUtils.mkdir_p(trial_dir)
      File.write(File.join(workspace, "PROMPT.md"), "Review the payment race.")
      fake = write_fake_container(directory, success_events, "diagnostic gpt-6.1-sol", 0)
      harness = TrialHarness.new(base_options(results: directory, container_bin: fake))

      result = harness.send(:execute_one, "gpt-6.1-sol", "blind123", trial_dir, workspace)

      assert_equal 0, result.fetch("exit_status")
      assert_equal 2, result.fetch("completed_turns")
      assert_equal({ "input_tokens" => 34, "cached_input_tokens" => 8, "output_tokens" => 14 }, result.fetch("usage"))
      blind_output = File.read(File.join(directory, "blind_outputs", "blind123.md"))
      assert_includes blind_output, "[MODEL]"
      refute_includes blind_output, "gpt-6.1-sol"
      raw_output = File.read(File.join(trial_dir, "response.md"))
      assert_includes raw_output, "gpt-6.1-sol"
      metadata = JSON.parse(File.read(File.join(trial_dir, "run_meta.json")))
      assert_equal Digest::SHA256.hexdigest(raw_output), metadata.fetch("raw_response_sha256")
      refute File.exist?(File.join(trial_dir, "codex-events.jsonl"))
      refute File.exist?(File.join(trial_dir, "transcript.jsonl"))
      refute_includes File.read(File.join(trial_dir, "run_meta.json")), "diagnostic gpt-6.1-sol"
    end
  end

  def test_execute_one_rejects_nonzero_exit_missing_turn_or_missing_answer
    invalid_cases = [
      [success_events, 1],
      ["{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Answer\"}}\n", 0],
      ["{\"type\":\"turn.completed\",\"usage\":{}}\n", 0]
    ]

    invalid_cases.each do |events, status|
      Dir.mktmpdir("fake-container-invalid") do |directory|
        workspace = File.join(directory, "workspace")
        trial_dir = File.join(directory, "trial")
        FileUtils.mkdir_p(workspace)
        FileUtils.mkdir_p(trial_dir)
        File.write(File.join(workspace, "PROMPT.md"), "Prompt")
        fake = write_fake_container(directory, events, "", status)
        harness = TrialHarness.new(base_options(results: directory, container_bin: fake))

        error = assert_raises(RuntimeError) do
          harness.send(:execute_one, "gpt-6.1-sol", "blindbad", trial_dir, workspace)
        end
        assert_match(/invalid trial/, error.message)
        assert File.file?(File.join(trial_dir, "invalid_run.json"))
        refute File.exist?(File.join(directory, "blind_outputs", "blindbad.md"))
      end
    end
  end

  def success_events
    <<~JSON
      {"type":"item.completed","item":{"type":"agent_message","text":"I am gpt-6.1-sol. Diagnosis: a race; add durable uniqueness."}}
      {"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":5}}
      {"type":"item.completed","item":{"type":"agent_message","text":"Final answer from gpt-6.1-sol: persist one attempt per order."}}
      {"type":"turn.completed","usage":{"input_tokens":24,"cached_input_tokens":6,"output_tokens":9}}
    JSON
  end

  def write_fake_container(directory, stdout, stderr, exit_status)
    executable = File.join(directory, "fake-container")
    File.write(executable, <<~RUBY)
      #!#{RbConfig.ruby}
      STDIN.read
      STDOUT.write(#{stdout.dump})
      STDERR.write(#{stderr.dump})
      exit #{exit_status}
    RUBY
    File.chmod(0o700, executable)
    executable
  end
end
