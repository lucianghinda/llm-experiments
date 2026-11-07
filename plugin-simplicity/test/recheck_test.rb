require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative '../scripts/recheck'

class RecheckTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @trial = File.join(@dir, 'trial')
    @repo = File.join(@dir, 'repo')
    @catalog = File.join(@dir, 'catalog')
    FileUtils.mkdir_p([@trial, @repo, @catalog])
    system('git', 'init', '-q', @repo, exception: true)
    system('git', '-C', @repo, 'config', 'user.name', 'Pilot', exception: true)
    system('git', '-C', @repo, 'config', 'user.email', 'pilot@example.invalid', exception: true)
    File.write(File.join(@repo, 'app'), 'baseline')
    system('git', '-C', @repo, 'add', '.', exception: true)
    system('git', '-C', @repo, 'commit', '-qm', 'baseline', exception: true)
    Pilot.snapshot(@repo, @trial, Pilot.git(@repo, 'rev-parse', 'HEAD').strip)
    File.write(File.join(@catalog, 'tasks.json'), JSON.generate([{'id' => 'task', 'checks' => [['true'], ['true']]}]))
    @meta = {'status' => 'awaiting_review', 'workspace_stable' => true, 'restoration_verified' => true, 'agent_run' => {'exit' => 0, 'timed_out' => false}, 'catalog' => @catalog, 'task' => 'task'}
    File.write(File.join(@trial, 'meta.json'), JSON.generate(@meta))
    File.write(File.join(@trial, 'checks.json'), JSON.generate([{'exit' => 0}, {'exit' => 1}]))
    File.write(File.join(@trial, 'check-0.stdout'), 'passed')
    File.write(File.join(@trial, 'check-1.stderr'), 'failed to create container XPC timeout containerCreate')
    File.write(File.join(@trial, 'transcript.txt'), 'preserve')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_success_preserves_original_and_updates_only_after_pass
    meta_before = File.binread(File.join(@trial, 'meta.json'))
    snapshot_before = File.binread(File.join(@trial, 'snapshot.json'))
    checker = ->(_meta, _task, _root, _out) { [{'exit' => 0}, {'exit' => 0}] }
    assert Pilot.recheck(@trial, checker: checker)
    meta = JSON.parse(File.read(File.join(@trial, 'meta.json')))
    assert_equal 'complete', meta['status']
    assert_equal meta_before, File.binread(File.join(@trial, 'verification-attempts', 'original', 'meta.json'))
    assert_equal snapshot_before, File.binread(File.join(@trial, 'snapshot.json'))
    assert_equal 'preserve', File.read(File.join(@trial, 'transcript.txt'))
    audit = JSON.parse(File.read(File.join(@trial, meta['recheck_attempt'], 'audit.json')))
    assert_equal Digest::SHA256.hexdigest(meta_before), audit['original_meta_sha256']
    assert audit['passed']
  end

  def test_failed_retry_and_non_infrastructure_failure_leave_canonical_untouched
    before = File.binread(File.join(@trial, 'meta.json'))
    refute Pilot.recheck(@trial, checker: ->(*) { [{'exit' => 0}, {'exit' => 1}] })
    assert_equal before, File.binread(File.join(@trial, 'meta.json'))
    File.write(File.join(@trial, 'check-1.stderr'), 'assertion failed')
    assert_raises(RuntimeError) { Pilot.recheck(@trial, checker: ->(*) { raise 'must not run' }) }
  end
end
