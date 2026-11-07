# frozen_string_literal: true
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require_relative '../scripts/container_adapter'

root = File.expand_path('..', __dir__)
Dir.mktmpdir('pilot-check-independence') do |temp|
  %w[report identifiers cancellation csv_import].each do |task|
    workspace = File.join(temp, task)
    FileUtils.cp_r(File.join(root, 'fixtures', task), workspace)
    # A subject can weaken or delete its helper; hidden assertions must survive.
    File.write(File.join(workspace, 'test_support.rb'), 'raise "subject helper loaded"')
    output, status = Open3.capture2e(RbConfig.ruby, File.join(root, 'checks', "#{task}.rb"), chdir: workspace)
    raise "#{task} accepted unfinished code" if status.success?
    raise "#{task} loaded subject assertion helper" if output.include?('subject helper loaded')
  end
end
Dir.mktmpdir('baseline-helper') do |dir|
  repo = File.join(dir, 'repo')
  out = File.join(dir, 'out')
  FileUtils.mkdir_p([repo, out, File.join(dir, 'checks')])
  Pilot.git(repo, 'init', '-q')
  Pilot.git(repo, 'config', 'user.name', 'Pilot')
  Pilot.git(repo, 'config', 'user.email', 'pilot@example.invalid')
  FileUtils.mkdir_p(File.join(repo, 'test'))
  File.write(File.join(repo, 'test_support.rb'), "HELPER = 'original'\n")
  File.write(File.join(repo, 'test', 'check.rb'), "require_relative '../test_support'\nabort unless HELPER == 'original'\n")
  Pilot.git(repo, 'add', '.')
  Pilot.git(repo, 'commit', '-qm', 'baseline')
  baseline = Pilot.git(repo, 'rev-parse', 'HEAD').strip
  File.write(File.join(repo, 'test_support.rb'), "HELPER = 'tampered'\n")
  Pilot.snapshot(repo, out, baseline)
  task = {'checks' => [[RbConfig.ruby, 'test/check.rb']]}
  raise 'fake checker used tampered helper' unless Pilot.fake_checks(out, task, dir).first['exit'] == 0
  seen = false
  executor = lambda do |argv, timeout:, input:|
    if argv[0, 2] == %w[container run]
      mount = argv.find { |arg| arg.end_with?(':/workspace/app') }
      seen = File.read(File.join(mount.delete_suffix(':/workspace/app'), 'test_support.rb')).include?("'original'")
    end
    {'exit' => 0, 'timed_out' => false, 'stdout' => '', 'stderr' => ''}
  end
  Pilot::ContainerAdapter.new(executor: executor).checks({'image' => 'image'}, task, dir, out)
  raise 'live checker used tampered helper' unless seen
end
puts 'Four private acceptance helpers remain independent of subject test support'
