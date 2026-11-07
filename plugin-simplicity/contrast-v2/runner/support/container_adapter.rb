# frozen_string_literal: true
require 'fileutils'
require 'json'
require 'securerandom'
require 'tmpdir'
require 'tempfile'
require 'digest'
require_relative 'harness'

module Pilot
  class ContainerAdapter
    def initialize(executor: Pilot.method(:command))
      @executor = executor
    end

    def run(options, task, condition, root, out, workspace)
      image = options['image'].to_s
      raise ArgumentError, 'explicit container image required' if image.empty?
      agent = options.fetch('agent')
      raise ArgumentError, 'unknown agent' unless %w[claude codex].include?(agent)
      auth = options['auth_file'].to_s
      raise ArgumentError, 'credential file required' unless File.file?(auth)
      raise ArgumentError, 'fixture contains no baseline git repository' unless File.directory?(File.join(workspace, '.git'))
      plugin = condition['plugin_path']
      raise ArgumentError, 'plugin directory missing' if plugin && !File.directory?(plugin)
      name = "pilot-#{SecureRandom.hex(10)}"
      timeout = options.fetch('timeout', 900)
      result = {'container' => name, 'adapter' => 'apple-container', 'status' => 'infrastructure_failure', 'exported' => false, 'workspace_stable' => false, 'image' => image}
      begin
        if plugin
          result['plugin_commit'] = Pilot.git(plugin, 'rev-parse', 'HEAD').strip
          result['plugin_tree'] = Pilot.git(plugin, 'rev-parse', 'HEAD^{tree}').strip
          raise 'plugin has tracked changes' unless Pilot.git(plugin, 'status', '--porcelain', '--untracked-files=no').empty?
          plugin_snapshot = File.join(out, 'plugin-source')
          FileUtils.mkdir_p(plugin_snapshot)
          archive, error, status = Open3.capture3('git', '-C', plugin, 'archive', '--format=tar', result['plugin_commit'])
          raise "plugin archive failed: #{error}" unless status.success?
          _, error, status = Open3.capture3('tar', '-xf', '-', '-C', plugin_snapshot, stdin_data: archive)
          raise "plugin extraction failed: #{error}" unless status.success?
          Pilot.git(plugin_snapshot, 'init', '-q')
          Pilot.git(plugin_snapshot, 'config', 'user.name', 'Pilot')
          Pilot.git(plugin_snapshot, 'config', 'user.email', 'pilot@example.invalid')
          Pilot.git(plugin_snapshot, 'add', '-f', '-A')
          snapshot_tree = Pilot.git(plugin_snapshot, 'write-tree').strip
          raise 'plugin snapshot tree differs from source' unless snapshot_tree == result['plugin_tree']
          Pilot.git(plugin_snapshot, 'commit', '-qm', 'Plugin snapshot')
        end
        image_info = execute(['container', 'image', 'inspect', image], timeout: 30)
        result['image_inspect'] = image_info['stdout'] if success?(image_info)
        launch = ['container', 'run', '--detach', '--cpus', '4', '--memory', '6g', '--name', name,
                  '--volume', "#{workspace}:/workspace/app"]
        launch += ['--volume', "#{File.expand_path(plugin_snapshot)}:/plugin:ro"] if plugin
        launch += [image, 'sleep', 'infinity']
        begin
          started = execute(launch, timeout: 120)
          raise "container launch failed: #{started['stderr']}" unless success?(started)
          setup = <<~'SCRIPT'
            require 'fileutils'
            abort 'agent image must run as a non-root user' if Process.uid.zero?
            FileUtils.mkdir_p(['/workspace/app', '/home/agent/pilot-session/home/.claude', '/home/agent/pilot-session/codex'])
            target = ARGV.fetch(0) == 'claude' ? '/home/agent/pilot-session/home/.claude/.credentials.json' : '/home/agent/pilot-session/codex/auth.json'
            File.binwrite(target, STDIN.read)
            File.chmod(0600, target)
          SCRIPT
          seeded = execute(exec_command(name, ['ruby', '-e', setup, agent]), timeout: 120, input: File.binread(auth))
          raise "credential setup failed" unless success?(seeded)
          if plugin
            manifest = JSON.parse(File.read(File.join(plugin_snapshot, '.claude-plugin', 'marketplace.json')))
            marketplace = manifest.fetch('name')
            plugin_name = manifest.fetch('plugins').fetch(0).fetch('name')
            [['plugin', 'marketplace', 'add', '/plugin'], ['plugin', 'install', "#{plugin_name}@#{marketplace}"]].each do |args|
              args[1] = 'add' if agent == 'codex' && args[1] == 'install'
              checked(exec_command(name, [agent, *args]), timeout: 120)
            end
          end
          version = execute(exec_command(name, [agent, "--version"]), timeout: 30)
          result["cli_version"] = version["stdout"].to_s.strip if success?(version)
          inventory_args = [agent, "plugin", "list"]
          inventory_args << "--json" if agent == "codex"
          inventory = execute(exec_command(name, inventory_args), timeout: 120)
          raise "plugin inventory unavailable" unless success?(inventory)
          result["plugin_inventory"] = inventory["stdout"]
          if agent == "codex"
            installed = JSON.parse(inventory.fetch("stdout")).fetch("installed")
            expected = plugin && "#{plugin_name}@#{marketplace}"
            if expected && !installed.any? { |entry| entry["pluginId"] == expected && entry["installed"] == true && entry["enabled"] == true }
              raise "installed and enabled plugin missing from inventory"
            end
          elsif plugin && !inventory["stdout"].to_s.include?(plugin_name)
            raise "installed plugin missing from inventory"
          end
          prompt = File.read(File.expand_path(task.fetch('prompt').fetch(options.fetch('track')), root))
          cmd = if agent == 'claude'
            ['claude', '-p', '--verbose', '--output-format', 'stream-json', '--model', options.fetch('model'), '--permission-mode', 'bypassPermissions']
          else
            ['codex', 'exec', '--json', '--dangerously-bypass-approvals-and-sandbox', '-m', options.fetch('model'), '-']
          end
          run = execute(exec_command(name, cmd), timeout: timeout, input: prompt)
          result['auth_refresh_saved'] = persist_credentials(name, agent, auth) if success?(run)
          File.write(File.join(out, 'transcript.txt'), run.fetch('stdout', ''))
          File.write(File.join(out, 'stderr.txt'), run.fetch('stderr', ''))
          result['agent_run'] = run.reject { |key, _| %w[stdout stderr].include?(key) }
          result['status'] = run['timed_out'] ? 'timeout' : success?(run) ? 'awaiting_review' : 'agent_failure'
          result['continuation'] = 'manual_review_required'
          run.fetch('stdout', '').each_line do |line|
            begin
              event = JSON.parse(line)
              result['session_id'] ||= event['session_id'] || event['thread_id']
              result['actual_model'] ||= event['model']
            rescue JSON::ParserError
              next
            end
          end
        ensure
          result.merge!(export_worktrees(name, out))
          stopped = execute(["container", "stop", name], timeout: 120)
          result['workspace_stable'] = success?(stopped)
          result['error'] = 'container could not be stopped; workspace may still be changing' unless result['workspace_stable']
          result['exported'] = File.directory?(File.join(workspace, '.git'))
          result['status'] = 'infrastructure_failure' unless result['exported'] && result['workspace_stable']
        end
      rescue StandardError => e
        result['error'] ||= "#{e.class}: #{e.message}"
        result['status'] = 'infrastructure_failure'
      end
      result
    end

# Restore the verified snapshot into a disposable workspace. Hidden checks
# are mounted only into this separate checker, never the subject container.
def checks(options, task, root, out)
  raise 'snapshot failed verification' unless Pilot.verify_restore(out)
  image = options.fetch('image')
  dir = Dir.mktmpdir('pilot-checker')
  name = "pilot-checker-#{SecureRandom.hex(10)}"
  stopped = false
  lifecycle = {'container' => name, 'stopped' => false, 'deleted' => false}
  begin
    work = Pilot.restore(out, File.join(dir, 'app'))
    baseline = Pilot.restore(out, File.join(dir, 'baseline'), version: 'baseline')
    Pilot.restore_baseline_tests(work, baseline)
    launch = ['container', 'run', '--detach', '--cpus', '4', '--memory', '6g', '--name', name, '--volume', "#{work}:/workspace/app", '--volume', "#{File.join(root, 'checks')}:/audit/checks:ro", '--workdir', '/workspace/app', image, 'sleep', 'infinity']
    lifecycle['launch_attempted'] = true
    checked(launch, timeout: 120)
    task.fetch('checks').map.with_index do |argv, index|
      command = argv.map { |arg| arg.gsub('{root}', '/audit').gsub('{workspace}', '/workspace/app') }
      invocation = ['container', 'exec', '--workdir', '/workspace/app', name, '/bin/bash', '-lc', 'exec "$@"', 'pilot', *command]
      result = execute(invocation, timeout: options.fetch('timeout', 900))
      File.write(File.join(out, "check-#{index}.stdout"), result.delete('stdout').to_s)
      File.write(File.join(out, "check-#{index}.stderr"), result.delete('stderr').to_s)
      result
    end
  ensure
    if lifecycle['launch_attempted']
      begin
        stopped = success?(execute(['container', 'stop', name], timeout: 120))
        lifecycle['stopped'] = stopped
        lifecycle['deleted'] = success?(execute(['container', 'delete', name], timeout: 120)) if stopped
      rescue StandardError
        lifecycle['error'] = 'checker lifecycle command failed'
      end
    else
      stopped = true
    end
    lifecycle['retained_workspace'] = dir unless stopped
    File.write(File.join(out, 'checker-lifecycle.json'), JSON.pretty_generate(lifecycle))
    FileUtils.remove_entry(dir) if stopped
    raise 'checker stop or delete failed; see checker-lifecycle.json' if lifecycle['launch_attempted'] && (!lifecycle['stopped'] || !lifecycle['deleted'])
  end
end

    # The caller must supply a reviewed response and recorded session id.
    def resume(container:, agent:, session_id:, response:, model:, timeout:, auth_file: nil, out:)
      raise ArgumentError, "session id and response required" if session_id.to_s.strip.empty? || response.to_s.strip.empty?
      raise ArgumentError, "timeout must be positive" unless timeout.is_a?(Numeric) && timeout.positive? && timeout.finite?
      argv = case agent
      when "claude"
        ["claude", "-p", "--verbose", "--output-format", "stream-json", "--model", model, "--permission-mode", "bypassPermissions", "--resume", session_id]
      when "codex"
        ["codex", "exec", "resume", "--json", "--dangerously-bypass-approvals-and-sandbox", "-m", model, session_id, "-"]
      else
        raise ArgumentError, "unknown agent"
      end
      result = {"exit" => nil, "timed_out" => false, "workspace_stable" => false, "stdout" => "", "stderr" => ""}
      started = false
      begin
        checked(["container", "start", container], timeout: 120)
        started = true
        result.merge!(execute(exec_command(container, argv), timeout: timeout, input: response))
        result['auth_refresh_saved'] = persist_credentials(container, agent, auth_file) if auth_file && success?(result)
      rescue StandardError => e
        result["error"] = "#{e.class}: #{e.message}"
      ensure
        if started
          begin
            result.merge!(export_worktrees(container, out))
            stopped = execute(["container", "stop", container], timeout: 120)
            result["workspace_stable"] = success?(stopped)
            result["stop_error"] = "container could not be stopped" unless result["workspace_stable"]
          rescue StandardError => e
            result["stop_error"] = "#{e.class}: #{e.message}"
          end
        end
      end
      result
    end

    private

    def export_worktrees(container, out)
      listing = execute(exec_command(container, ['git', '-C', '/workspace/app', 'worktree', 'list', '--porcelain', '-z']), timeout: 30)
      raise 'worktree discovery failed' unless success?(listing)
      paths = listing.fetch('stdout', '').split("\0").filter_map { |field| field.delete_prefix('worktree ') if field.start_with?('worktree ') }
      raise 'worktree discovery returned no paths' if paths.empty?
      entries = paths.each_with_index.map do |path, index|
        raise 'unsafe worktree path' unless path.start_with?('/') && File.expand_path(path) == path
        session = '/home/agent/pilot-session'
        raise 'worktree overlaps private session' if path == session || path.start_with?(session + '/') || session.start_with?(path == '/' ? '/' : path + '/')
        archive = execute(exec_command(container, ['tar', '-C', path, '-czf', '-', '.']), timeout: 300)
        raise 'worktree archive failed' unless success?(archive) && !archive.fetch('stdout', '').empty?
        name = "worktree-#{index + 1}.tar.gz"
        bytes = archive.fetch('stdout')
        File.binwrite(File.join(out, name), bytes)
        {'path' => path, 'archive' => name, 'sha256' => Digest::SHA256.hexdigest(bytes)}
      end
      {'all_worktrees_saved' => true, 'worktrees' => entries}
    rescue StandardError
      {'all_worktrees_saved' => false, 'worktree_export_error' => 'worktree discovery or export failed'}
    end

    # Credential bytes remain in memory and the private seed only; never return
    # them or the command's output to the trial artifacts.
    def persist_credentials(container, agent, auth_file)
      path = agent == 'claude' ? '/home/agent/pilot-session/home/.claude/.credentials.json' : '/home/agent/pilot-session/codex/auth.json'
      read = execute(exec_command(container, ['cat', path]), timeout: 30)
      return false unless success?(read)
      candidate = read.fetch('stdout', '')
      stored = File.binread(auth_file)
      old = JSON.parse(stored)
      fresh = JSON.parse(candidate)
      return false unless old.is_a?(Hash) && fresh.is_a?(Hash) && preserves_strings?(old, fresh) && token_present?(fresh)
      return false if stored == candidate
      Tempfile.create(['.pilot-auth-', '.tmp'], File.dirname(File.expand_path(auth_file))) do |file|
        file.chmod(0600)
        file.binmode
        file.write(candidate)
        file.flush
        file.fsync
        File.rename(file.path, auth_file)
      end
      true
    rescue StandardError
      false
    end

    def preserves_strings?(old, fresh)
      old.all? do |key, value|
        replacement = fresh[key]
        if value.is_a?(Hash)
          replacement.is_a?(Hash) && preserves_strings?(value, replacement)
        elsif value.is_a?(String) && !value.empty?
          replacement.is_a?(String) && !replacement.empty?
        else
          true
        end
      end
    end

    def token_present?(value)
      value.any? do |key, item|
        item.is_a?(Hash) ? token_present?(item) : key.match?(/token|api.?key/i) && item.is_a?(String) && !item.empty?
      end
    end

    def execute(argv, timeout:, input: '')
      @executor.call(argv, timeout: timeout, input: input)
    end

    def checked(argv, timeout:)
      result = execute(argv, timeout: timeout)
      raise "container setup failed: #{result['stderr']}" unless success?(result)
      result
    end

    def success?(result)
      result['exit'] == 0 && !result['timed_out']
    end

    def exec_command(name, argv)
      ['container', 'exec', '--interactive', '--workdir', '/workspace/app', '--env', 'HOME=/home/agent/pilot-session/home', '--env', 'CODEX_HOME=/home/agent/pilot-session/codex', '--env', 'CLAUDE_CONFIG_DIR=/home/agent/pilot-session/home/.claude', name, '/bin/bash', '-lc', 'exec "$@"', 'pilot', *argv]
    end
  end

  def self.live_checks(options, task, root, out)
    ContainerAdapter.new.checks(options, task, root, out)
  end

  def self.live_run(options, task, condition, root, out, workspace)
    ContainerAdapter.new.run(options, task, condition, root, out, workspace)
  end
end
