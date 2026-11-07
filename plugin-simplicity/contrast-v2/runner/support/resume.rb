#!/usr/bin/env ruby
# frozen_string_literal: true
require "optparse"
require_relative "container_adapter"
options = {}
OptionParser.new do |p|
  %w[trial session-id response-file output].each { |key| p.on("--#{key} VALUE") { |v| options[key.tr("-", "_")] = v } }
  p.on("--timeout SECONDS", Float) { |v| options["timeout"] = v }
end.parse!
begin
  %w[trial session_id response_file output].each { |key| raise "--#{key.tr('_', '-')} required" if options[key].to_s.empty? }
  trial = File.expand_path(options.fetch("trial"))
  out = File.expand_path(options.fetch("output"))
  raise "output already exists" if File.exist?(out)
  meta = JSON.parse(File.read(File.join(trial, "meta.json")))
  raise "trial is not awaiting review" unless meta["status"] == "awaiting_review" && meta["workspace_stable"]
  raise "restoration verification required" unless meta["restoration_verified"]
  raise "session ID differs from recorded session" if meta["session_id"] && meta["session_id"] != options["session_id"]
  timeout = options.fetch("timeout", meta.fetch("timeout"))
  raise "timeout must be positive" unless timeout.is_a?(Numeric) && timeout.positive? && timeout.finite?
  response = File.read(options.fetch("response_file"))
  raise "empty response" if response.strip.empty?
  FileUtils.mkdir_p(out)
  File.write(File.join(out, "response.txt"), response)
  workspace = meta.fetch("workspace_path", File.join(trial, "workspace"))
  continuation = meta.merge("source_trial" => trial, "workspace_path" => workspace, "session_id" => options["session_id"], "status" => "infrastructure_failure", "started_at" => Time.now.utc.iso8601, "restoration_verified" => false)
  %w[checks_passed checks_error snapshot_error error agent_run finished_at all_worktrees_saved worktrees worktree_export_error].each { |key| continuation.delete(key) }
  continuation['all_worktrees_saved'] = false
  begin
    result = Pilot::ContainerAdapter.new.resume(container: meta.fetch("container"), agent: meta.fetch("agent"), session_id: options["session_id"], response: response, model: meta.fetch("model"), timeout: timeout, auth_file: meta.fetch("auth_file"), out: out)
    File.write(File.join(out, "transcript.txt"), result.delete("stdout").to_s)
    File.write(File.join(out, "stderr.txt"), result.delete("stderr").to_s)
    continuation["agent_run"] = result
    %w[all_worktrees_saved worktrees worktree_export_error].each { |key| continuation[key] = result.delete(key) if result.key?(key) }
    continuation["workspace_stable"] = result["workspace_stable"]
    continuation["status"] = result["timed_out"] ? "timeout" : result["exit"] == 0 && !result["error"] ? "awaiting_review" : "agent_failure"
    raise "container may still be writing; workspace retained without snapshot" unless result["workspace_stable"]
    baseline = JSON.parse(File.read(File.join(trial, "snapshot.json"))).fetch("baseline")
    Pilot.snapshot(workspace, out, baseline)
    continuation["restoration_verified"] = Pilot.verify_restore(out)
    if continuation["restoration_verified"]
      root = File.expand_path(meta.fetch("catalog"))
      task = JSON.parse(File.read(File.join(root, "tasks.json"))).find { |entry| entry["id"] == meta.fetch("task") }
      raise "task missing from catalog" unless task
      begin
        checks = Pilot.live_checks(meta, task, root, out)
        File.write(File.join(out, "checks.json"), JSON.pretty_generate(checks))
        continuation["checks_passed"] = checks.empty? ? nil : checks.all? { |check| check["exit"] == 0 && !check["timed_out"] }
        continuation["status"] = "complete" if continuation["status"] == "awaiting_review" && continuation["checks_passed"]
      rescue StandardError => e
        continuation["checks_error"] = "#{e.class}: #{e.message}"
      end
    end
  rescue StandardError => e
    continuation["error"] = "#{e.class}: #{e.message}"
  ensure
    continuation["finished_at"] = Time.now.utc.iso8601
    File.write(File.join(out, "meta.json"), JSON.pretty_generate(continuation))
  end
  puts JSON.pretty_generate(continuation)
  exit(continuation["status"] == "complete" && continuation["restoration_verified"] ? 0 : 1)
rescue StandardError => e
  warn e.message
  exit 2
end
