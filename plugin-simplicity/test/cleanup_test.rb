require_relative '../fixtures/report/test_support'
require_relative '../scripts/cleanup'
require 'tmpdir'

class CleanupTest < TestSupport::Test
  def test_requires_verified_stopped_trial_and_preserves_workspace
    Dir.mktmpdir do |dir|
      workspace = File.join(dir, 'workspace')
      FileUtils.mkdir_p(workspace)
      File.write(File.join(workspace, 'work'), 'keep')
      File.write(File.join(dir, 'final.bundle'), 'bundle')
      File.write(File.join(dir, 'meta.json'), JSON.generate('container' => 'pilot-0123456789abcdefabcd', 'restoration_verified' => true, 'workspace_stable' => true))
      calls = []
      runner = lambda do |argv, timeout:, input:|
        calls << argv
        {'exit' => 0, 'timed_out' => false, 'stdout' => JSON.generate({'state' => {'status' => 'stopped'}})}
      end
      assert_raises(RuntimeError) { Pilot.cleanup(dir, reviewed_complete: false, executor: runner, verifier: ->(_) { true }) }
      assert_raises(RuntimeError) { Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { false }) }
      assert_equal [], calls
      meta_path = File.join(dir, 'meta.json')
      meta = JSON.parse(File.read(meta_path))
      File.write(meta_path, JSON.generate(meta.merge('all_worktrees_saved' => false)))
      assert_raises(RuntimeError) { Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { true }) }
      assert_equal [], calls
      File.write(meta_path, JSON.generate(meta))
      archive = File.join(dir, 'worktree-1.tar.gz')
      File.write(archive, 'archive')
      retained = meta.merge('all_worktrees_saved' => true, 'worktrees' => [{'archive' => File.basename(archive), 'sha256' => Digest::SHA256.file(archive).hexdigest}])
      File.write(meta_path, JSON.generate(retained))
      File.write(archive, 'corrupted')
      assert_raises(RuntimeError) { Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { true }) }
      assert_equal [], calls
      File.write(meta_path, JSON.generate(meta))
      result = Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { true })
      assert_equal 'pilot-0123456789abcdefabcd', result['container']
      assert_equal ['container', 'delete', result['container']], calls.last
      assert_equal 'keep', File.read(File.join(workspace, 'work'))
      assert_equal 'bundle', File.read(File.join(dir, 'final.bundle'))
    end
  end

  def test_running_or_unknown_state_refuses_delete
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'meta.json'), JSON.generate('container' => 'pilot-0123456789abcdefabcd', 'restoration_verified' => true, 'workspace_stable' => true))
      %w[running unknown].each do |state|
        calls = []
        runner = lambda do |argv, timeout:, input:|
          calls << argv
          {'exit' => 0, 'timed_out' => false, 'stdout' => JSON.generate({'state' => {'status' => state}})}
        end
        assert_raises(RuntimeError) { Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { true }) }
        assert_equal 1, calls.size
      end
    end
  end

  def test_top_level_status_and_identity
    Dir.mktmpdir do |dir|
      name = 'pilot-0123456789abcdefabcd'
      File.write(File.join(dir, 'meta.json'), JSON.generate('container' => name, 'restoration_verified' => true, 'workspace_stable' => true))
      %w[running stopped].each do |status|
        calls = []
        runner = lambda do |argv, timeout:, input:|
          calls << argv
          {'exit' => 0, 'timed_out' => false, 'stdout' => JSON.generate([{'status' => status, 'configuration' => {'id' => name}}])}
        end
        if status == 'running'
          assert_raises(RuntimeError) { Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { true }) }
          assert_equal 1, calls.size
        else
          Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { true })
          assert_equal ['container', 'delete', name], calls.last
        end
      end
      calls = []
      runner = lambda do |argv, timeout:, input:|
        calls << argv
        {'exit' => 0, 'timed_out' => false, 'stdout' => JSON.generate([{'status' => 'stopped', 'configuration' => {'id' => 'different'}}])}
      end
      assert_raises(RuntimeError) { Pilot.cleanup(dir, reviewed_complete: true, executor: runner, verifier: ->(_) { true }) }
      assert_equal 1, calls.size
    end
  end
end
