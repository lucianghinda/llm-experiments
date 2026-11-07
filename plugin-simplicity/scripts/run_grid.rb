#!/usr/bin/env ruby
# frozen_string_literal: true
require "optparse"
require "json"
require "rbconfig"
require "digest"
require_relative "harness"

# Reviewers may write disposition.json beside a terminal trial's meta.json:
# {"category":"task_failure", "meta_sha256":"...", "reason":"...", "no_pending_question":true}
# Other categories are agent_failure, timeout, and infrastructure_failure.
def reviewed_terminal?(path, meta)
  disposition_path = File.join(path, 'disposition.json')
  return false unless File.file?(disposition_path)
  record = JSON.parse(File.read(disposition_path))
  categories = {'task_failure' => 'awaiting_review', 'agent_failure' => 'agent_failure', 'timeout' => 'timeout', 'infrastructure_failure' => 'infrastructure_failure'}
  raise 'invalid terminal disposition' unless categories.key?(record['category']) && categories[record['category']] == meta['status'] &&
    record['reason'].is_a?(String) && !record['reason'].strip.empty? &&
    record['meta_sha256'] == Digest::SHA256.file(File.join(path, 'meta.json')).hexdigest
  raise 'pending question requires continuation' if record['category'] == 'task_failure' && record['no_pending_question'] != true
  archives = meta['worktrees']
  retained = archives.is_a?(Array) && !archives.empty? && archives.all? do |entry|
    name = entry['archive']
    name.is_a?(String) && name.match?(/\Aworktree-\d+\.tar\.gz\z/) && File.file?(File.join(path, name)) &&
      Digest::SHA256.file(File.join(path, name)).hexdigest == entry['sha256']
  end
  raise 'terminal trial not safely retained' unless meta['workspace_stable'] == true && meta['all_worktrees_saved'] == true && retained && meta['restoration_verified'] == true && Pilot.verify_restore(path)
  true
end
options = {}
parser = OptionParser.new do |p|
  %w[catalog output claude-model codex-model fake-command tasks image claude-auth-file codex-auth-file].each { |name| p.on("--#{name} VALUE") { |v| options[name.tr("-", "_")] = v } }
  p.on("--repeats N", Integer) { |v| options["repeats"] = v }
  p.on("--seed N", Integer) { |v| options["seed"] = v }
  p.on("--dry-run") { options["dry_run"] = true }
  p.on("--resume") { options["resume"] = true }
end
begin
  parser.parse!
  raise "unexpected arguments" unless ARGV.empty?
  if options["resume"]
    raise "--resume requires only --output" unless options.keys.sort == %w[output resume] && !options["output"].to_s.empty?
    output = File.expand_path(options.fetch("output"))
    manifest = JSON.parse(File.read(File.join(output, "grid.json")))
    options = manifest.fetch("options")
    raise "grid output differs from manifest" unless File.expand_path(options.fetch("output")) == output
    cells = manifest.fetch("cells")
  else
  options = {"repeats" => 2, "seed" => 1, "tasks" => "report,csv_import"}.merge(options)
  %w[catalog output claude_model codex_model].each { |k| raise "--#{k.tr('_', '-')} required" if options[k].to_s.empty? }
  raise "repeats must be positive" unless options["repeats"].positive?
  tasks = JSON.parse(File.read(File.join(options["catalog"], "tasks.json"))).reject { |t| t["blocked"] }
  if options["tasks"]
    ids = options["tasks"].split(",")
    missing = ids - tasks.map { |task| task.fetch("id") }
    raise "unknown or blocked tasks: #{missing.join(", ")}" unless missing.empty?
    tasks = tasks.select { |task| ids.include?(task.fetch("id")) }
  end
  conditions = JSON.parse(File.read(File.join(options["catalog"], "conditions.json")))
  rng = Random.new(options["seed"])
  cells = []
  tasks.each do |task|
    %w[claude codex].each do |agent|
      %w[natural specified].each do |track|
        options["repeats"].times do |repeat|
          conditions.shuffle(random: rng).each do |condition|
            cells << {"task" => task.fetch("id"), "agent" => agent, "track" => track,
                      "condition" => condition.fetch("id"), "repeat" => repeat + 1}
          end
        end
      end
    end
  end
  if options["dry_run"]
    puts JSON.pretty_generate({"seed" => options["seed"], "cells" => cells})
    exit 0
  end
  unless options["fake_command"]
    %w[image claude_auth_file codex_auth_file].each { |key| raise "--#{key.tr("_", "-")} required" if options[key].to_s.empty? }
  end
  raise "output already exists" if File.exist?(options["output"])
  FileUtils.mkdir_p(options["output"])
  File.write(File.join(options["output"], "grid.json"), JSON.pretty_generate({"options" => options, "cells" => cells}))
  end
  failures = 0
  cells.each_with_index do |cell, index|
    cell_path = File.expand_path(File.join(options["output"], format("%04d", index + 1)))
    if File.exist?(cell_path)
      current = cell_path
      visited = []
      loop do
        raise "cell #{index + 1}: continuation cycle" if visited.include?(current)
        visited << current
        meta = JSON.parse(File.read(File.join(current, "meta.json")))
        %w[task agent track condition].each { |key| raise "cell #{index + 1}: #{key} mismatch" unless meta[key] == cell[key] }
        raise "cell #{index + 1}: model mismatch" unless meta["model"] == options.fetch("#{cell['agent']}_model")
        if reviewed_terminal?(current, meta)
          warn "Cell #{index + 1}: retained terminal failure (#{meta['status']})."
          break
        end
        if %w[complete fake_complete].include?(meta["status"])
          raise "cell #{index + 1}: fake result in live grid" if meta["status"] == "fake_complete" && !options["fake_command"]
          checks = JSON.parse(File.read(File.join(current, "checks.json")))
          valid_checks = checks.is_a?(Array) && !checks.empty? && checks.all? { |check| check["exit"] == 0 && !check["timed_out"] }
          raise "cell #{index + 1}: incomplete verification" unless meta["restoration_verified"] && meta["checks_passed"] && valid_checks && Pilot.verify_restore(current)
          break
        end
        raise "cell #{index + 1} requires review: #{current} (#{meta['status']})" unless meta["status"] == "awaiting_review"
        children = Dir.glob(File.join(cell_path, "continuations", "*", "meta.json")).select do |path|
          child = JSON.parse(File.read(path))
          File.expand_path(child.fetch("source_trial")) == current
        end
        raise "cell #{index + 1} requires review: #{current} (#{children.length} continuations)" unless children.length == 1
        current = File.dirname(children.first)
      end
      next
    end
    argv = [RbConfig.ruby, File.join(__dir__, "run_trial.rb"), "--catalog", options["catalog"],
            "--output", cell_path,
            "--model", options.fetch("#{cell['agent']}_model")]
    if options["fake_command"]
      argv.concat(["--fake-command", options["fake_command"]])
    else
      argv.concat(["--image", options["image"], "--auth-file", options.fetch("#{cell["agent"]}_auth_file")])
    end
    %w[task agent track condition].each { |key| argv.concat(["--#{key}", cell.fetch(key)]) }
    unless system(*argv)
      failures += 1
      warn "Grid paused after cell #{index + 1}; remaining cells are recorded in grid.json."
      break
    end
  end
  exit(failures.zero? ? 0 : 1)
rescue StandardError => e
  warn e.message
  exit 2
end
