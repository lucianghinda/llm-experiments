# frozen_string_literal: true
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "time"

module Pilot
  module_function

  def command(argv, timeout:, chdir: nil, input: "")
    options = {pgroup: true}
    options[:chdir] = chdir if chdir
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out = +""
    err = +""
    timed_out = false
    status = nil
    deadline = started + timeout
    Open3.popen3(*argv, **options) do |stdin, stdout, stderr, wait|
      writer = Thread.new do
        begin
          stdin.write(input)
        rescue IOError, Errno::EPIPE, Errno::EBADF
          nil
        ensure
          stdin.close rescue nil
        end
      end
      readers = [reader(stdout, out), reader(stderr, err)]
      completed = wait.join(remaining(deadline))
      completed = false unless writer.join(remaining(deadline))
      readers.each { |thread| completed = false unless thread.join(remaining(deadline)) }
      unless completed
        timed_out = true
        # Detached descendants may outlive the command and need caller cleanup.
        # Do not signal a process group after its leader has been reaped.
        Process.kill("KILL", -wait.pid) if wait.alive? rescue nil
        writer.kill
        readers.each(&:kill)
        [writer, *readers].each { |thread| thread.join(0.2) }
        [stdin, stdout, stderr].each { |stream| stream.close rescue nil }
        status = wait.value
      else
        status = wait.value
        writer.join
        readers.each(&:join)
      end
    end
    {"argv" => argv, "exit" => status.exitstatus, "timed_out" => timed_out,
     "stdout" => out, "stderr" => err,
     "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started}
  end

  def reader(stream, output)
    Thread.new do
      loop { output << stream.readpartial(16_384) }
    rescue EOFError, IOError, Errno::EBADF
      nil
    end
  end

  def remaining(deadline)
    [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
  end

  def git(dir, *args)
    out, err, status = Open3.capture3("git", "-C", dir, *args)
    raise "git #{args.first}: #{err}" unless status.success?
    out
  end

  def answer(question, answers)
    answers[question.strip]
  end

  def dry_run(spec)
    puts JSON.pretty_generate(spec.merge("dry_run" => true))
  end

  # Commit to a private temporary index/ref so even untracked files and commits
  # made by the subject are captured, without changing its working tree.
  def snapshot(repo, out, baseline)
    snapshot_all(repo, out, baseline)
  end

  def snapshot_all(repo, out, baseline)
    git(repo, "update-ref", "refs/pilot/baseline", baseline)
    git(repo, "bundle", "create", File.join(out, "baseline.bundle"), "refs/pilot/baseline")
    tree = Dir.mktmpdir("pilot-index") do |dir|
      env = {"GIT_INDEX_FILE" => File.join(dir, "index")}
      [["read-tree", "HEAD"], ["add", "-f", "-A"], ["write-tree"]].map do |args|
        result, err, status = Open3.capture3(env, "git", "-C", repo, *args)
        raise err unless status.success?
        result.strip
      end.last
    end
    parent = git(repo, "rev-parse", "HEAD").strip
    env = {"GIT_AUTHOR_NAME" => "Pilot", "GIT_AUTHOR_EMAIL" => "pilot@example.invalid", "GIT_COMMITTER_NAME" => "Pilot", "GIT_COMMITTER_EMAIL" => "pilot@example.invalid"}
    commit, err, status = Open3.capture3(env, "git", "-C", repo, "commit-tree", tree, "-p", parent, stdin_data: "Pilot snapshot\n")
    raise err unless status.success?
    git(repo, "update-ref", "refs/pilot/final", commit.strip)
    git(repo, "bundle", "create", File.join(out, "final.bundle"), "refs/pilot/final")
    File.write(File.join(out, "change.patch"), git(repo, "diff", "--binary", baseline, commit.strip))
    File.write(File.join(out, "snapshot.json"), JSON.pretty_generate({"baseline" => baseline, "final" => commit.strip, "tree" => tree}))
  end

  def restore(out, destination, version: "final")
    raise "destination already exists" if File.exist?(destination)
    info = JSON.parse(File.read(File.join(out, "snapshot.json")))
    raise "invalid version" unless %w[baseline final].include?(version)
    FileUtils.mkdir_p(destination)
    git(destination, "init", "-q")
    git(destination, "fetch", File.join(File.expand_path(out), "#{version}.bundle"), "refs/pilot/#{version}:refs/pilot/#{version}")
    git(destination, "checkout", "-q", "--detach", "refs/pilot/#{version}")
    expected = info.fetch(version)
    raise "restored commit mismatch" unless git(destination, "rev-parse", "HEAD").strip == expected
    destination
  end

  # Fake-adapter checks run on a restored disposable copy. Live checks must run
  # in a separate checker container; never execute model-written code on host.
  def restore_baseline_tests(work, baseline)
    %w[test test_support.rb].each do |name|
      source = File.join(baseline, name)
      next unless File.exist?(source)
      destination = File.join(work, name)
      FileUtils.rm_rf(destination)
      FileUtils.cp_r(source, destination)
    end
  end

  def fake_checks(out, task, root, timeout: 120)
    Dir.mktmpdir do |dir|
      final = restore(out, File.join(dir, "final"))
      baseline = restore(out, File.join(dir, "baseline"), version: "baseline")
      restore_baseline_tests(final, baseline)
      Array(task["checks"]).map do |argv|
        expanded = argv.map { |arg| arg.gsub("{root}", root).gsub("{workspace}", final) }
        command(expanded, chdir: final, timeout: timeout)
      end
    end
  end

  def verify_restore(out)
    info = JSON.parse(File.read(File.join(out, "snapshot.json")))
    Dir.mktmpdir do |dir|
      baseline = restore(out, File.join(dir, "baseline"), version: "baseline")
      final = restore(out, File.join(dir, "final"))
      return false unless git(final, "rev-parse", "HEAD^{tree}").strip == info.fetch("tree")
      patch = File.join(File.expand_path(out), "change.patch")
      git(baseline, "apply", "--index", "--binary", patch) unless File.zero?(patch)
      git(baseline, "write-tree").strip == info.fetch("tree")
    end
  rescue StandardError
    false
  end
end
