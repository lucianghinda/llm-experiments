require_relative '../fixtures/report/test_support'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative '../scripts/container_adapter'

class ContainerAdapterTest < TestSupport::Test
  def assert_includes(collection, value)
    assert collection.include?(value)
  end

  def refute_includes(collection, value)
    refute collection.include?(value)
  end
  def test_isolation_plugin_install_and_stopped_container
    Dir.mktmpdir do |dir|
      workspace = File.join(dir, 'workspace')
      out = File.join(dir, 'out')
      plugin = File.join(dir, 'plugin')
      FileUtils.mkdir_p([File.join(workspace, '.git'), out, File.join(plugin, '.claude-plugin')])
      File.write(File.join(plugin, '.claude-plugin', 'marketplace.json'), JSON.generate('name' => 'market', 'plugins' => [{'name' => 'plugin'}]))
      File.symlink('marketplace.json', File.join(plugin, '.claude-plugin', 'linked.json'))
      system("git", "init", "-q", plugin, exception: true)
      system("git", "-C", plugin, "config", "user.name", "Pilot", exception: true)
      system("git", "-C", plugin, "config", "user.email", "pilot@example.invalid", exception: true)
      system("git", "-C", plugin, "add", ".", exception: true)
      system("git", "-C", plugin, "commit", "-qm", "fixture", exception: true)
      File.write(File.join(plugin, 'AGENTS.md'), 'private plan')
      File.write(File.join(dir, 'credentials'), JSON.generate('tokens' => {'access_token' => 'old-secret'}))
      File.write(File.join(dir, 'prompt'), 'implement this')
      calls = []
      executor = lambda do |argv, timeout:, input:|
        calls << [argv, input, timeout]
        stdout = if argv.include?('list')
          JSON.generate('installed' => [{'pluginId' => 'plugin@market', 'installed' => true, 'enabled' => true}])
        elsif argv.include?('cat')
          JSON.generate('tokens' => {'access_token' => 'new-secret'})
        else
          ''
        end
        {'exit' => 0, 'timed_out' => false, 'stdout' => stdout, 'stderr' => ''}
      end
      adapter = Pilot::ContainerAdapter.new(executor: executor)
      options = {'agent' => 'codex', 'image' => 'example:1', 'auth_file' => File.join(dir, 'credentials'), 'track' => 'natural', 'model' => 'model', 'timeout' => 10}
      result = adapter.run(options, {'prompt' => {'natural' => 'prompt'}}, {'plugin_path' => plugin}, dir, out, workspace)
      assert_equal 'awaiting_review', result['status']
      assert result['auth_refresh_saved']
      refute JSON.generate(result).include?('new-secret')
      refute File.read(File.join(out, 'transcript.txt')).include?('new-secret')
      assert result['exported']
      inventory = calls.find { |argv, _input, _timeout| argv.include?('list') && argv.include?('--json') }
      assert_equal 120, inventory.fetch(2)
      launch = calls.find { |argv, _| argv[0, 2] == %w[container run] }.first
      assert_includes launch, "#{workspace}:/workspace/app"
      snapshot = File.join(out, 'plugin-source')
      assert_includes launch, "#{snapshot}:/plugin:ro"
      refute File.exist?(File.join(snapshot, 'AGENTS.md'))
      assert File.symlink?(File.join(snapshot, '.claude-plugin', 'linked.json'))
      assert result['plugin_commit']
      assert result['plugin_tree']
      clone = File.join(dir, 'clone')
      system('git', 'clone', '-q', snapshot, clone, exception: true)
      assert_equal result['plugin_tree'], Pilot.git(clone, 'rev-parse', 'HEAD^{tree}').strip
      assert_equal '1', Pilot.git(clone, 'rev-list', '--count', 'HEAD').strip
      refute File.exist?(File.join(clone, 'AGENTS.md'))
      assert calls.any? { |argv, _| argv.include?('CODEX_HOME=/home/agent/pilot-session/codex') }
      refute_includes launch, out
      refute_includes launch, '--rm'
      assert calls.any? { |argv, _| argv.include?('marketplace') && argv.include?('/plugin') }
      assert calls.any? { |argv, _| argv.include?('plugin@market') }
      assert calls.any? { |argv, input| argv.include?('exec') && input == 'implement this' }
      assert calls.select { |argv, input| argv[0, 2] == %w[container exec] && !input.empty? }.all? { |argv, _| argv.include?('--interactive') }
      assert_equal ['container', 'stop', result.fetch('container')], calls.last.first
      assert_equal 'manual_review_required', result['continuation']
      File.write(File.join(plugin, '.claude-plugin', 'marketplace.json'), '{}')
      calls.clear
      dirty = adapter.run(options, {'prompt' => {'natural' => 'prompt'}}, {'plugin_path' => plugin}, dir, out, workspace)
      assert_equal 'infrastructure_failure', dirty['status']
      assert dirty['error'].include?('plugin has tracked changes')
      refute calls.any? { |argv, _| argv[0, 2] == %w[container run] }
    end
  end

  def test_image_is_mandatory
    adapter = Pilot::ContainerAdapter.new(executor: ->(*) { raise 'must not execute' })
    assert_raises(ArgumentError) { adapter.run({}, {}, {}, '', '', '') }
  end

  def test_refresh_saves_only_valid_nondowngraded_credentials
    Dir.mktmpdir do |dir|
      auth = File.join(dir, 'auth.json')
      original = JSON.generate('tokens' => {'access_token' => 'old-secret', 'refresh_token' => 'old-refresh'}, 'account' => 'id')
      File.write(auth, original)
      candidate = JSON.generate('tokens' => {'access_token' => 'new-secret', 'refresh_token' => 'new-refresh'}, 'account' => 'id')
      adapter = Pilot::ContainerAdapter.new(executor: ->(*, **){ {'exit' => 0, 'timed_out' => false, 'stdout' => candidate} })
      assert adapter.send(:persist_credentials, 'container', 'codex', auth)
      assert_equal candidate, File.read(auth)
      assert_equal 0600, File.stat(auth).mode & 0777
      candidate = JSON.generate('tokens' => {'access_token' => '', 'refresh_token' => ''}, 'account' => 'id')
      refute adapter.send(:persist_credentials, 'container', 'codex', auth)
      assert File.read(auth).include?('new-secret')
      candidate = '{}'
      refute adapter.send(:persist_credentials, 'container', 'codex', auth)
      candidate = 'invalid'
      refute adapter.send(:persist_credentials, 'container', 'codex', auth)
    end
  end

  def test_codex_inventory_rejects_disabled_plugin
    Dir.mktmpdir do |dir|
      workspace = File.join(dir, 'workspace')
      plugin = File.join(dir, 'plugin')
      FileUtils.mkdir_p([File.join(workspace, '.git'), File.join(plugin, '.claude-plugin')])
      File.write(File.join(plugin, '.claude-plugin', 'marketplace.json'), JSON.generate('name' => 'market', 'plugins' => [{'name' => 'plugin'}]))
      system('git', 'init', '-q', plugin, exception: true)
      system('git', '-C', plugin, 'config', 'user.name', 'Pilot', exception: true)
      system('git', '-C', plugin, 'config', 'user.email', 'pilot@example.invalid', exception: true)
      system('git', '-C', plugin, 'add', '.', exception: true)
      system('git', '-C', plugin, 'commit', '-qm', 'fixture', exception: true)
      File.write(File.join(dir, 'auth'), 'secret')
      executor = lambda do |argv, timeout:, input:|
        inventory = JSON.generate('installed' => [{'pluginId' => 'plugin@market', 'installed' => true, 'enabled' => false}])
        {'exit' => 0, 'timed_out' => false, 'stdout' => argv.include?('list') ? inventory : '', 'stderr' => ''}
      end
      options = {'agent' => 'codex', 'image' => 'image', 'auth_file' => File.join(dir, 'auth')}
      result = Pilot::ContainerAdapter.new(executor: executor).run(options, {}, {'plugin_path' => plugin}, dir, dir, workspace)
      assert_equal 'infrastructure_failure', result['status']
      assert result['error'].include?('installed and enabled plugin missing')
    end
  end

  def test_resume_requires_explicit_response_and_stops_container
    calls = []
    adapter = Pilot::ContainerAdapter.new(executor: ->(argv, timeout:, input:) { calls << [argv, input]; {'exit' => 0, 'timed_out' => false} })
    assert_raises(ArgumentError) { adapter.resume(container: 'c', agent: 'claude', session_id: '', response: 'yes', model: 'm', timeout: 2, out: '/tmp') }
    adapter.resume(container: 'c', agent: 'claude', session_id: 'session', response: 'answer', model: 'm', timeout: 2, out: '/tmp')
    assert_equal ['container', 'start', 'c'], calls.first.first
    assert_includes calls[1].first, '--resume'
    assert_equal 'answer', calls[1].last
    assert_equal ['container', 'stop', 'c'], calls.last.first
  end

  def test_worktree_export_archives_declared_paths_without_serializing_bytes
    Dir.mktmpdir do |dir|
      calls = []
      bytes = "\x1f\x8b\x00secret binary".b
      executor = lambda do |argv, timeout:, input:|
        calls << argv
        stdout = argv.include?('worktree') ? "worktree /workspace/app\0HEAD abc\0\0worktree /workspace/other path\0HEAD def\0\0" : bytes
        {'exit' => 0, 'timed_out' => false, 'stdout' => stdout}
      end
      adapter = Pilot::ContainerAdapter.new(executor: executor)
      result = adapter.send(:export_worktrees, 'c', dir)
      assert result['all_worktrees_saved']
      assert_equal bytes, File.binread(File.join(dir, 'worktree-2.tar.gz'))
      assert calls.any? { |argv| argv.include?('/workspace/other path') }
      refute JSON.generate(result).include?('secret binary')
      failed = Pilot::ContainerAdapter.new(executor: ->(*, **) { {'exit' => 1, 'timed_out' => false} }).send(:export_worktrees, 'c', dir)
      refute failed['all_worktrees_saved']
      assert failed['worktree_export_error']
    end
  end
def test_setup_failure_reports_container_and_unstable_stop
  Dir.mktmpdir do |dir|
    workspace = File.join(dir, 'workspace')
    FileUtils.mkdir_p(File.join(workspace, '.git'))
    File.write(File.join(dir, 'auth'), 'secret')
    executor = lambda do |argv, timeout:, input:|
      failed = argv[0, 2] == ['container', 'stop'] || argv.include?('-e')
      {'exit' => failed ? 1 : 0, 'timed_out' => false, 'stdout' => '', 'stderr' => 'failed'}
    end
    options = {'agent' => 'codex', 'image' => 'image', 'auth_file' => File.join(dir, 'auth')}
    result = Pilot::ContainerAdapter.new(executor: executor).run(options, {}, {}, dir, dir, workspace)
    assert_equal 'infrastructure_failure', result['status']
    assert result['container'].start_with?('pilot-')
    refute result['workspace_stable']
    assert result['error'].include?('could not be stopped')
  end
end

def test_checker_uses_restored_disposable_workspace_and_private_mount
  Dir.mktmpdir do |dir|
    repo = File.join(dir, 'repo')
    out = File.join(dir, 'out')
    FileUtils.mkdir_p([repo, out, File.join(dir, 'checks')])
    system('git', 'init', '-q', repo, exception: true)
    system('git', '-C', repo, 'config', 'user.name', 'Pilot', exception: true)
    system('git', '-C', repo, 'config', 'user.email', 'pilot@example.invalid', exception: true)
    File.write(File.join(repo, 'file'), 'original')
    system('git', '-C', repo, 'add', '.', exception: true)
    system('git', '-C', repo, 'commit', '-qm', 'baseline', exception: true)
    baseline = Pilot.git(repo, 'rev-parse', 'HEAD').strip
    Pilot.snapshot(repo, out, baseline)
    calls = []
    executor = lambda do |argv, timeout:, input:|
      calls << argv
      {'exit' => 0, 'timed_out' => false, 'stdout' => 'ok', 'stderr' => ''}
    end
    task = {'checks' => [['ruby', '{root}/checks/a.rb', '{workspace}']]}
    results = Pilot::ContainerAdapter.new(executor: executor).checks({'image' => 'image'}, task, dir, out)
    assert_equal 0, results.first['exit']
    assert_includes calls.first, "#{dir}/checks:/audit/checks:ro"
    assert calls.any? { |argv| argv.include?('/audit/checks/a.rb') }
    assert calls.any? { |argv| argv.include?('/workspace/app') }
    refute calls.first.any? { |argument| argument == "#{repo}:/workspace/app" }
    assert_equal 'ok', File.read(File.join(out, 'check-0.stdout'))
    assert_equal 1, calls.count { |argv| argv[0, 2] == %w[container run] }
    assert_equal ['container', 'stop'], calls[-2][0, 2]
    assert_equal ['container', 'delete'], calls[-1][0, 2]
  end
end

def test_checker_retains_workspace_if_stop_fails
  Dir.mktmpdir do |dir|
    repo = File.join(dir, 'repo')
    out = File.join(dir, 'out')
    FileUtils.mkdir_p([repo, out, File.join(dir, 'checks')])
    system('git', 'init', '-q', repo, exception: true)
    system('git', '-C', repo, 'config', 'user.name', 'Pilot', exception: true)
    system('git', '-C', repo, 'config', 'user.email', 'pilot@example.invalid', exception: true)
    File.write(File.join(repo, 'file'), 'original')
    system('git', '-C', repo, 'add', '.', exception: true)
    system('git', '-C', repo, 'commit', '-qm', 'baseline', exception: true)
    Pilot.snapshot(repo, out, Pilot.git(repo, 'rev-parse', 'HEAD').strip)
    executor = lambda do |argv, timeout:, input:|
      {'exit' => argv[0, 2] == %w[container stop] ? 1 : 0, 'timed_out' => false, 'stdout' => '', 'stderr' => ''}
    end
    assert_raises(RuntimeError) { Pilot::ContainerAdapter.new(executor: executor).checks({'image' => 'image'}, {'checks' => [['true']]}, dir, out) }
    lifecycle = JSON.parse(File.read(File.join(out, 'checker-lifecycle.json')))
    refute lifecycle['stopped']
    assert File.directory?(lifecycle.fetch('retained_workspace'))
    FileUtils.remove_entry(lifecycle.fetch('retained_workspace'))
  end
end

def test_ambiguous_launch_is_stopped_and_container_id_retained
  Dir.mktmpdir do |dir|
    workspace = File.join(dir, 'workspace')
    FileUtils.mkdir_p(File.join(workspace, '.git'))
    File.write(File.join(dir, 'auth'), 'secret')
    calls = []
    executor = lambda do |argv, timeout:, input:|
      calls << argv
      failed = argv[0, 2] == ['container', 'run']
      {'exit' => failed ? nil : 0, 'timed_out' => failed, 'stdout' => '', 'stderr' => 'timeout'}
    end
    options = {'agent' => 'codex', 'image' => 'image', 'auth_file' => File.join(dir, 'auth')}
    result = Pilot::ContainerAdapter.new(executor: executor).run(options, {}, {}, dir, dir, workspace)
    assert_equal 'infrastructure_failure', result['status']
    assert result['workspace_stable']
    assert_equal ['container', 'stop', result['container']], calls.last
    assert result['error'].include?('container launch failed')
  end
end

end
