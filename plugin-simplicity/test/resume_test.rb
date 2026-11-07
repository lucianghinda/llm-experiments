require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require_relative '../scripts/harness'

class ResumeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @trial = File.join(@dir, 'trial')
    @workspace = File.join(@trial, 'workspace')
    @catalog = File.join(@dir, 'catalog')
    FileUtils.mkdir_p([@workspace, File.join(@catalog, 'checks')])
    system('git', 'init', '-q', @workspace, exception: true)
    system('git', '-C', @workspace, 'config', 'user.name', 'Pilot', exception: true)
    system('git', '-C', @workspace, 'config', 'user.email', 'pilot@example.invalid', exception: true)
    File.write(File.join(@workspace, 'app'), 'baseline')
    system('git', '-C', @workspace, 'add', '.', exception: true)
    system('git', '-C', @workspace, 'commit', '-qm', 'baseline', exception: true)
    baseline = Pilot.git(@workspace, 'rev-parse', 'HEAD').strip
    Pilot.snapshot(@workspace, @trial, baseline)
    File.write(File.join(@catalog, 'tasks.json'), JSON.generate([{id: 'task', checks: [['ruby', '{root}/checks/check.rb']]}]))
    auth = File.join(@dir, 'auth.json')
    File.write(auth, JSON.generate(tokens: {access_token: 'old', refresh_token: 'old-refresh'}))
    File.write(File.join(@trial, 'meta.json'), JSON.generate(status: 'awaiting_review', workspace_stable: true, restoration_verified: true, agent: 'codex', model: 'model', container: 'container-id', timeout: 10, session_id: 'session', catalog: @catalog, task: 'task', image: 'image', auth_file: auth))
    @response = File.join(@dir, 'answer')
    File.write(@response, 'continue')
    @bin = File.join(@dir, 'bin')
    FileUtils.mkdir_p(@bin)
    File.write(File.join(@bin, 'container'), "#!#{RbConfig.ruby}\nexit 4 if ARGV.first == 'exec' && ENV['FAKE_FAILURE']\nputs 'done'\n")
    FileUtils.chmod(0755, File.join(@bin, 'container'))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def run_resume(*extra, failure: false)
    out = File.join(@dir, 'continuation')
    env = {'PATH' => "#{@bin}:#{ENV.fetch('PATH')}", 'FAKE_FAILURE' => failure ? '1' : nil}
    command = [RbConfig.ruby, File.expand_path('../scripts/resume.rb', __dir__), '--trial', @trial, '--session-id', 'session', '--response-file', @response, '--output', out, *extra]
    stdout, stderr, status = Open3.capture3(env, *command)
    [out, stdout, stderr, status]
  end

  def test_resume_snapshots_and_runs_checks
    out, _, stderr, status = run_resume
    assert status.success?, stderr
    meta = JSON.parse(File.read(File.join(out, 'meta.json')))
    assert_equal 'complete', meta['status']
    assert meta['restoration_verified']
    assert meta['checks_passed']
    assert File.exist?(File.join(out, 'checks.json'))
  end

  def test_failed_command_keeps_restorable_snapshot
    out, _, _, status = run_resume(failure: true)
    refute status.success?
    meta = JSON.parse(File.read(File.join(out, 'meta.json')))
    assert_equal 'agent_failure', meta['status']
    assert meta['restoration_verified']
    assert Pilot.verify_restore(out)
  end

  def test_rejects_nonpositive_timeout_and_wrong_session
    out, _, stderr, status = run_resume('--timeout', '0')
    refute status.success?
    assert_includes stderr, 'timeout must be positive'
    refute File.exist?(out)
    out, _, stderr, status = run_resume('--session-id', 'different')
    refute status.success?
    assert_includes stderr, 'session ID differs'
    refute File.exist?(out)
  end

  def test_failed_start_does_not_inherit_previous_worktree_export
    path = File.join(@trial, 'meta.json')
    meta = JSON.parse(File.read(path))
    meta['all_worktrees_saved'] = true
    meta['worktrees'] = [{'archive' => 'old'}]
    File.write(path, JSON.generate(meta))
    File.write(File.join(@bin, 'container'), "#!#{RbConfig.ruby}\nexit 1 if ARGV.first == 'start'\nexit 0\n")
    out, _, _, status = run_resume
    refute status.success?
    continuation = JSON.parse(File.read(File.join(out, 'meta.json')))
    assert_equal false, continuation['all_worktrees_saved']
    refute continuation.key?('worktrees')
  end
end
