# frozen_string_literal: true

require "json"
require "rbconfig"
require "open3"
require "base64"
require "tmpdir"
require "fileutils"

HARNESS = File.expand_path("../scripts/harness.rb", __dir__)

def equal(expected, actual)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end

def test_normal_command_output_is_unchanged
  source = "require #{HARNESS.dump}; require 'json'; require 'rbconfig'; print JSON.generate(Pilot.command([RbConfig.ruby, '-e', \"STDOUT.write('out'); STDERR.write('err')\"], timeout: 2))"
  output, error, status = Open3.capture3(RbConfig.ruby, "-e", source)
  raise error unless status.success?
  result = JSON.parse(output)
  equal(0, result["exit"])
  equal(false, result["timed_out"])
  equal("out", result["stdout"])
  equal("err", result["stderr"])

  writer_source = "require #{HARNESS.dump}; require 'json'; require 'rbconfig'; result = Pilot.command([RbConfig.ruby, '-e', 'exit 0'], timeout: 2, input: 'x' * 1_000_000); print JSON.generate('exit' => result['exit'], 'timed_out' => result['timed_out'])"
  writer_output, writer_error, writer_status = Open3.capture3(RbConfig.ruby, "-e", writer_source)
  raise writer_error unless writer_status.success?
  writer_result = JSON.parse(writer_output)
  equal(0, writer_result["exit"])
  equal(false, writer_result["timed_out"])

  binary_source = "require #{HARNESS.dump}; require 'json'; require 'rbconfig'; require 'base64'; result = Pilot.command([RbConfig.ruby, '-e', \"STDOUT.binmode; STDOUT.write([0, 255, 1].pack('C*'))\"], timeout: 2); print JSON.generate('exit' => result['exit'], 'timed_out' => result['timed_out'], 'stdout_base64' => Base64.strict_encode64(result['stdout']))"
  binary_output, binary_error, binary_status = Open3.capture3(RbConfig.ruby, "-e", binary_source)
  raise binary_error unless binary_status.success?
  binary_result = JSON.parse(binary_output)
  equal(false, binary_result["timed_out"])
  equal([0, 255, 1], Base64.decode64(binary_result["stdout_base64"]).bytes)
end

def test_timeout_returns_with_partial_output_when_detached_descendant_holds_pipes
  Dir.mktmpdir("command-timeout") do |dir|
    pid_file = File.join(dir, "descendant.pid")
    result_file = File.join(dir, "result.json")
    stderr_file = File.join(dir, "driver.stderr")
    grandchild = 'Process.setpgrp; File.write(ARGV.fetch(0), Process.pid); STDOUT.write("descendant-out"); STDOUT.flush; STDERR.write("descendant-err"); STDERR.flush; sleep 30'
    parent = 'Process.spawn(RbConfig.ruby, "-e", ARGV.fetch(1), ARGV.fetch(0)); STDOUT.write("partial-out\n"); STDOUT.flush; STDERR.write("partial-err\n"); STDERR.flush; sleep 30'
    driver = <<~RUBY
      require #{HARNESS.dump}
      require "json"
      require "rbconfig"
      result = Pilot.command([RbConfig.ruby, "-e", #{parent.dump}, #{pid_file.dump}, #{grandchild.dump}], timeout: 0.2)
      File.write(#{result_file.dump}, JSON.generate(result))
    RUBY
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    driver_pid = Process.spawn(RbConfig.ruby, "-e", driver, out: File::NULL, err: stderr_file, pgroup: true)
    completed = wait_bounded(driver_pid, 2.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    raise "outer watchdog expired; driver did not return" unless completed

    result = JSON.parse(File.read(result_file))
    equal(true, result["timed_out"])
    equal(true, result["stdout"].include?("partial-out"))
    equal(true, result["stderr"].include?("partial-err"))
    raise "timeout cleanup exceeded 1.5 seconds: #{elapsed}" unless elapsed < 1.5
  ensure
    Process.kill("KILL", -driver_pid) if driver_pid rescue nil
    Process.wait(driver_pid) rescue nil
    Process.kill("KILL", File.read(pid_file).to_i) if File.file?(pid_file) rescue nil
  end
end

def test_exited_child_still_times_out_if_descendant_holds_pipes
  Dir.mktmpdir("command-io-timeout") do |dir|
    pid_file = File.join(dir, "descendant.pid")
    result_file = File.join(dir, "result.json")
    stderr_file = File.join(dir, "driver.stderr")
    grandchild = 'Process.setpgrp; File.write(ARGV.fetch(0), Process.pid); STDOUT.write("descendant-out"); STDOUT.flush; STDERR.write("descendant-err"); STDERR.flush; sleep 30'
    parent = 'Process.spawn(RbConfig.ruby, "-e", ARGV.fetch(1), ARGV.fetch(0)); STDOUT.write("early-out\n"); STDOUT.flush; STDERR.write("early-err\n"); STDERR.flush'
    driver = <<~RUBY
      require #{HARNESS.dump}
      require "json"
      require "rbconfig"
      result = Pilot.command([RbConfig.ruby, "-e", #{parent.dump}, #{pid_file.dump}, #{grandchild.dump}], timeout: 0.2)
      File.write(#{result_file.dump}, JSON.generate(result))
    RUBY
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    driver_pid = Process.spawn(RbConfig.ruby, "-e", driver, out: File::NULL, err: stderr_file, pgroup: true)
    completed = wait_bounded(driver_pid, 2.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    raise "outer watchdog expired; driver did not return" unless completed

    result = JSON.parse(File.read(result_file))
    equal(0, result["exit"])
    equal(true, result["timed_out"])
    equal(true, result["stdout"].include?("early-out"))
    equal(true, result["stderr"].include?("early-err"))
    raise "I/O timeout cleanup exceeded 1.5 seconds: #{elapsed}" unless elapsed < 1.5
  ensure
    Process.kill("KILL", -driver_pid) if driver_pid rescue nil
    Process.wait(driver_pid) rescue nil
    Process.kill("KILL", File.read(pid_file).to_i) if File.file?(pid_file) rescue nil
  end
end

def wait_bounded(pid, seconds)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  loop do
    return true if Process.waitpid(pid, Process::WNOHANG)
    return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.02
  end
end

test_normal_command_output_is_unchanged
puts "PASS test_normal_command_output_is_unchanged"
test_timeout_returns_with_partial_output_when_detached_descendant_holds_pipes
puts "PASS test_timeout_returns_with_partial_output_when_detached_descendant_holds_pipes"
test_exited_child_still_times_out_if_descendant_holds_pipes
puts "PASS test_exited_child_still_times_out_if_descendant_holds_pipes"
