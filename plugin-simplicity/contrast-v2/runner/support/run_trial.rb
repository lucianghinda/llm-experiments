#!/usr/bin/env ruby
# frozen_string_literal: true
require "optparse"
require "securerandom"
require_relative "harness"
require_relative "container_adapter"

options = {"timeout" => 900}
parser = OptionParser.new do |p|
  %w[task agent condition model track output catalog fake-command image auth-file].each do |name|
    p.on("--#{name} VALUE") { |v| options[name.tr("-", "_")] = v }
  end
  p.on("--timeout SECONDS", Float) { |v| options["timeout"] = v }
  p.on("--dry-run") { options["dry_run"] = true }
end
begin
  parser.parse!
  raise "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
  %w[task agent condition model track output catalog].each { |key| raise "--#{key} required" if options[key].to_s.empty? }
  raise "invalid agent" unless %w[claude codex].include?(options["agent"])
  raise "invalid track" unless %w[natural specified].include?(options["track"])
  raise "timeout must be positive" unless options["timeout"].positive?
  root = File.expand_path(options.fetch("catalog"))
  tasks = JSON.parse(File.read(File.join(root, "tasks.json")))
  conditions = JSON.parse(File.read(File.join(root, "conditions.json")))
  task = tasks.find { |t| t["id"] == options["task"] } or raise "unknown task"
  condition = conditions.find { |c| c["id"] == options["condition"] } or raise "unknown condition"
  raise "task blocked: #{task['blocked']}" if task["blocked"]
  prompt_path = File.expand_path(task.fetch("prompt").fetch(options["track"]), root)
  raise "prompt missing" unless File.file?(prompt_path)
  prompt = File.read(prompt_path)
  fixture = File.expand_path(task.fetch("fixture"), root)
  raise "fixture missing" unless Dir.exist?(fixture)
  if options["dry_run"]
    Pilot.dry_run(options.merge("fixture" => fixture, "plugin_path" => condition["plugin_path"]))
    exit 0
  end
  # The fake adapter is for harness verification, never a research result.
  unless options["fake_command"]
    raise "--image required for live execution" if options["image"].to_s.empty?
    raise "--auth-file required for live execution" if options["auth_file"].to_s.empty?
  end
  out = File.expand_path(options.fetch("output"))
  raise "output already exists" if File.exist?(out)
  FileUtils.mkdir_p(out)
  meta = options.merge("adapter" => options["fake_command"] ? "fake" : "container", "started_at" => Time.now.utc.iso8601, "status" => "infrastructure_failure")
  workspace = File.join(out, "workspace")
  baseline = nil
  begin
    FileUtils.cp_r(fixture, workspace)
    raise "fixture contains git history" if File.exist?(File.join(workspace, ".git"))
    Pilot.git(workspace, "init", "-q")
    Pilot.git(workspace, "config", "user.name", "Pilot")
    Pilot.git(workspace, "config", "user.email", "pilot@example.invalid")
    Pilot.git(workspace, "add", "-A")
    Pilot.git(workspace, "commit", "-qm", "Fixture baseline")
    baseline = Pilot.git(workspace, "rev-parse", "HEAD").strip
    File.write(File.join(out, "prompt.txt"), prompt)
    File.write(File.join(out, "transcript.txt"), "")
    File.write(File.join(out, "stderr.txt"), "")
    if options["fake_command"]
      result = Pilot.command([options["fake_command"]], timeout: options["timeout"], chdir: workspace,
                             input: prompt)
      File.write(File.join(out, "transcript.txt"), result.delete("stdout"))
      File.write(File.join(out, "stderr.txt"), result.delete("stderr"))
      meta["agent_run"] = result
      meta["status"] = result["timed_out"] ? "timeout" : result["exit"] == 0 ? "fake_complete" : "agent_failure"
    else
      meta["workspace_stable"] = false
      meta.merge!(Pilot.live_run(options, task, condition, root, out, workspace))
    end
  rescue StandardError => e
    meta["error"] = "#{e.class}: #{e.message}"
  ensure
    if baseline && meta["workspace_stable"] == false
      meta["snapshot_error"] = "container may still be writing; workspace retained without snapshot"
      meta["restoration_verified"] = false
    elsif baseline
      begin
        Pilot.snapshot(workspace, out, baseline)
        meta["restoration_verified"] = Pilot.verify_restore(out)
        if meta["restoration_verified"]
          begin
            checks = if options["fake_command"]
              Pilot.fake_checks(out, task, root)
            else
              Pilot.live_checks(options, task, root, out)
            end
            File.write(File.join(out, "checks.json"), JSON.pretty_generate(checks))
            meta["checks_passed"] = checks.empty? ? nil : checks.all? { |check| check["exit"] == 0 && !check["timed_out"] }
            meta["status"] = "complete" if meta["status"] == "awaiting_review" && meta["checks_passed"]
          rescue StandardError => e
            meta["checks_error"] = "#{e.class}: #{e.message}"
          end
        end
      rescue StandardError => e
        meta["snapshot_error"] = "#{e.class}: #{e.message}"
        meta["restoration_verified"] = false
      end
    end
    meta["finished_at"] = Time.now.utc.iso8601
    File.write(File.join(out, "meta.json"), JSON.pretty_generate(meta))
  end
  puts JSON.pretty_generate(meta)
  exit(%w[fake_complete complete].include?(meta["status"]) && meta["restoration_verified"] ? 0 : 1)
rescue StandardError => e
  warn e.message
  exit 2
end
