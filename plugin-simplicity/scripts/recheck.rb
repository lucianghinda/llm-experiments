#!/usr/bin/env ruby
# frozen_string_literal: true
require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'
require 'time'
require_relative 'container_adapter'

module Pilot
  def self.recheck(trial, checker: method(:live_checks))
    trial = File.expand_path(trial)
    meta_path = File.join(trial, 'meta.json')
    original_meta = File.binread(meta_path)
    meta = JSON.parse(original_meta)
    raise 'subject must be stopped and awaiting review' unless meta['status'] == 'awaiting_review' && meta['workspace_stable'] == true && meta.dig('agent_run', 'exit') == 0 && !meta.dig('agent_run', 'timed_out')
    raise 'snapshot verification required' unless meta['restoration_verified'] == true && verify_restore(trial)
    prior = JSON.parse(File.read(File.join(trial, 'checks.json')))
    raise 'no failed checks' unless prior.is_a?(Array) && prior.any? { |result| result['exit'] != 0 || result['timed_out'] }
    prior.each_with_index do |result, index|
      next if result['exit'] == 0 && !result['timed_out']
      stderr = File.read(File.join(trial, "check-#{index}.stderr"))
      raise 'failure is not evidenced container creation XPC timeout' unless stderr.match?(/failed to create container/i) && stderr.match?(/XPC.*timeout/i) && stderr.include?('containerCreate')
    end
    root = File.expand_path(meta.fetch('catalog'))
    task = JSON.parse(File.read(File.join(root, 'tasks.json'))).find { |entry| entry['id'] == meta.fetch('task') }
    raise 'task missing from catalog' unless task && task.fetch('checks').length == prior.length
    history = File.join(trial, 'verification-attempts')
    FileUtils.mkdir_p(history)
    original = File.join(history, 'original')
    unless File.exist?(original)
      Dir.mkdir(original)
      %w[meta.json checks.json].each { |name| FileUtils.cp(File.join(trial, name), original) }
      Dir.glob(File.join(trial, 'check-*.{stdout,stderr}')).each { |path| FileUtils.cp(path, original) }
    end
    attempt = File.join(history, "recheck-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.hex(4)}")
    Dir.mkdir(attempt)
    snapshot_files = %w[snapshot.json baseline.bundle final.bundle change.patch]
    hashes = snapshot_files.to_h { |name| [name, Digest::SHA256.file(File.join(trial, name)).hexdigest] }
    snapshot_files.each { |name| FileUtils.cp(File.join(trial, name), attempt) }
    started = Time.now.utc.iso8601
    begin
      checks = checker.call(meta, task, root, attempt)
      File.write(File.join(attempt, 'checks.json'), JSON.pretty_generate(checks))
      passed = checks.is_a?(Array) && checks.length == prior.length && !checks.empty? && checks.all? { |result| result['exit'] == 0 && !result['timed_out'] }
    rescue StandardError => e
      checks = nil
      passed = false
      error = "#{e.class}: #{e.message}"
    end
    audit = {'original_meta_sha256' => Digest::SHA256.hexdigest(original_meta), 'started_at' => started, 'finished_at' => Time.now.utc.iso8601, 'passed' => passed}
    audit['error'] = error if error
    File.write(File.join(attempt, 'audit.json'), JSON.pretty_generate(audit))
    return false unless passed
    raise 'trial changed during recheck' unless File.binread(meta_path) == original_meta && hashes.all? { |name, hash| Digest::SHA256.file(File.join(trial, name)).hexdigest == hash } && verify_restore(trial)
    updated = meta.merge('status' => 'complete', 'checks_passed' => true, 'recheck_attempt' => File.join('verification-attempts', File.basename(attempt)))
    updated.delete('checks_error')
    # The preserved original and attempt are authoritative if interrupted between writes.
    File.write(File.join(trial, 'checks.json.tmp'), JSON.pretty_generate(checks))
    File.rename(File.join(trial, 'checks.json.tmp'), File.join(trial, 'checks.json'))
    File.write(meta_path + '.tmp', JSON.pretty_generate(updated))
    File.rename(meta_path + '.tmp', meta_path)
    true
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise 'usage: ruby scripts/recheck.rb TRIAL_DIR' unless ARGV.length == 1
    exit(Pilot.recheck(ARGV.first) ? 0 : 1)
  rescue StandardError => e
    warn e.message
    exit 2
  end
end
