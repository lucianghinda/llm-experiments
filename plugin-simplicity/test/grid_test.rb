require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'digest'
require 'open3'
require 'rbconfig'
require_relative '../scripts/harness'

class GridResumeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @grid = File.join(@dir, 'grid')
    @cell = File.join(@grid, '0001')
    @repo = File.join(@dir, 'repo')
    FileUtils.mkdir_p([@cell, @repo])
    system('git', 'init', '-q', @repo, exception: true)
    system('git', '-C', @repo, 'config', 'user.name', 'Pilot', exception: true)
    system('git', '-C', @repo, 'config', 'user.email', 'pilot@example.invalid', exception: true)
    File.write(File.join(@repo, 'app'), 'baseline')
    system('git', '-C', @repo, 'add', '.', exception: true)
    system('git', '-C', @repo, 'commit', '-qm', 'baseline', exception: true)
    @baseline = Pilot.git(@repo, 'rev-parse', 'HEAD').strip
    @identity = {'task' => 'task', 'agent' => 'codex', 'track' => 'natural', 'condition' => 'ruby-plainspoken', 'model' => 'model'}
    options = {'output' => @grid, 'codex_model' => 'model', 'fake_command' => '/never/run'}
    File.write(File.join(@grid, 'grid.json'), JSON.generate('options' => options, 'cells' => [@identity.merge('repeat' => 1)]))
    complete(@cell)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def complete(path, extra = {})
    FileUtils.mkdir_p(path)
    Pilot.snapshot(@repo, path, @baseline)
    File.write(File.join(path, 'checks.json'), JSON.generate([{'exit' => 0, 'timed_out' => false}]))
    File.write(File.join(path, 'meta.json'), JSON.generate(@identity.merge('status' => 'complete', 'restoration_verified' => true, 'checks_passed' => true).merge(extra)))
  end

  def resume(*args)
    Open3.capture3(RbConfig.ruby, File.expand_path('../scripts/run_grid.rb', __dir__), '--resume', '--output', @grid, *args)
  end

  def test_skips_verified_cell_and_rejects_overrides
    assert resume.last.success?
    _, err, status = resume('--codex-model', 'different')
    refute status.success?
    assert_includes err, 'requires only --output'
  end

  def test_follows_unique_continuation_and_rejects_ambiguity
    File.write(File.join(@cell, 'meta.json'), JSON.generate(@identity.merge('status' => 'awaiting_review')))
    first = File.join(@cell, 'continuations', 'first')
    complete(first, 'source_trial' => @cell)
    assert resume.last.success?
    complete(File.join(@cell, 'continuations', 'second'), 'source_trial' => @cell)
    _, err, status = resume
    refute status.success?
    assert_includes err, '2 continuations'
  end

  def test_rejects_unverified_or_mismatched_cells
    File.write(File.join(@cell, 'checks.json'), '[]')
    _, err, status = resume
    refute status.success?
    assert_includes err, 'incomplete verification'
    complete(@cell, 'condition' => 'other')
    _, err, status = resume
    refute status.success?
    assert_includes err, 'condition mismatch'
  end

  def test_reviewed_terminal_failure_requires_intact_retention_and_bound_metadata
    archive = File.join(@cell, 'worktree-1.tar.gz')
    File.write(archive, 'archive')
    complete(@cell, 'status' => 'awaiting_review', 'workspace_stable' => true,
      'all_worktrees_saved' => true, 'worktrees' => [{'archive' => File.basename(archive), 'sha256' => Digest::SHA256.file(archive).hexdigest}])
    record = {'category' => 'task_failure', 'meta_sha256' => Digest::SHA256.file(File.join(@cell, 'meta.json')).hexdigest, 'reason' => 'reviewed acceptance failure'}
    disposition = File.join(@cell, 'disposition.json')
    File.write(disposition, JSON.generate(record))
    _, err, status = resume
    refute status.success?
    assert_includes err, 'pending question'
    record['no_pending_question'] = true
    File.write(disposition, JSON.generate(record))
    assert resume.last.success?
    File.write(archive, 'changed')
    _, err, status = resume
    refute status.success?
    assert_includes err, 'not safely retained'
    File.write(archive, 'archive')
    File.write(File.join(@cell, 'meta.json'), File.read(File.join(@cell, 'meta.json')) + "\n")
    _, err, status = resume
    refute status.success?
    assert_includes err, 'invalid terminal disposition'
  end
end
