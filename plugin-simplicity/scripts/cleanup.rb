#!/usr/bin/env ruby
# Explicitly destroy the retained container, including seeded credentials, only
# after continuation is complete and the snapshot has been verified. The trial
# workspace and all bundles remain untouched.
require 'json'
require 'time'
require 'digest'
require_relative 'harness'

module Pilot
  def self.cleanup(out, reviewed_complete:, executor: method(:command), verifier: method(:verify_restore))
    raise 'explicit --reviewed-complete required' unless reviewed_complete
    out = File.expand_path(out)
    meta = JSON.parse(File.read(File.join(out, 'meta.json')))
    raise 'recorded snapshot was not verified' unless meta['restoration_verified'] == true && verifier.call(out)
    raise 'workspace stability was not established' unless meta['workspace_stable'] == true
    raise 'worktree export was not completed' if meta.key?('all_worktrees_saved') && meta['all_worktrees_saved'] != true
    if meta['all_worktrees_saved'] == true
      worktrees = meta['worktrees']
      raise 'worktree archives missing or invalid' unless worktrees.is_a?(Array) && !worktrees.empty? && worktrees.all? do |entry|
        filename = entry['archive']
        filename.is_a?(String) && filename.match?(/\Aworktree-\d+\.tar\.gz\z/) &&
          File.file?(File.join(out, filename)) && Digest::SHA256.file(File.join(out, filename)).hexdigest == entry['sha256']
      end
    end
    name = meta.fetch('container')
    raise 'invalid trial container name' unless name.match?(/\Apilot-[0-9a-f]{20}\z/)
    inspected = executor.call(['container', 'inspect', name], timeout: 30, input: '')
    raise 'container inspection failed' unless inspected['exit'] == 0 && !inspected['timed_out']
    document = JSON.parse(inspected.fetch('stdout'))
    document = document.first if document.is_a?(Array) && document.length == 1
    raise 'ambiguous container inspection' unless document.is_a?(Hash)
    configuration = document['configuration']
    if configuration.is_a?(Hash) && configuration.key?('id')
      raise 'container inspection identity mismatch' unless configuration['id'] == name
    end
    state = document['state'] || document['State']
    status = if state.is_a?(Hash)
      state['status'] || state['Status']
    elsif state.is_a?(String)
      state
    else
      document['status']
    end
    raise 'container must be stopped before cleanup' unless %w[stopped exited].include?(status.to_s.downcase)
    deleted = executor.call(['container', 'delete', name], timeout: 120, input: '')
    raise 'container deletion failed' unless deleted['exit'] == 0 && !deleted['timed_out']
    record = {'container' => name, 'deleted_at' => Time.now.utc.iso8601, 'reviewed_complete' => true}
    File.write(File.join(out, 'cleanup.json'), JSON.pretty_generate(record) + "\n")
    record
  end
end

if $PROGRAM_NAME == __FILE__
  require 'optparse'
  reviewed = false
  parser = OptionParser.new { |p| p.on('--reviewed-complete') { reviewed = true } }
  begin
    parser.parse!
    raise 'usage: ruby scripts/cleanup.rb --reviewed-complete TRIAL_DIR' unless ARGV.length == 1
    puts JSON.pretty_generate(Pilot.cleanup(ARGV.first, reviewed_complete: reviewed))
  rescue StandardError => e
    warn e.message
    exit 1
  end
end
