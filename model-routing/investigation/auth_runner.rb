#!/usr/bin/env ruby
# Keeps Codex session state private to one container trial while safely carrying
# forward a rotated ChatGPT subscription credential.
require "fileutils"
require "json"
require "securerandom"

module CodexTrialAuth
  AUTH_FILE = "auth.json"

  module_function

  def seed(shared_home, private_home)
    FileUtils.mkdir_p(private_home, mode: 0o700)
    source = File.join(shared_home, AUTH_FILE)
    return false unless File.file?(source)

    FileUtils.cp(source, File.join(private_home, AUTH_FILE), preserve: true)
    true
  end

  def downgrade?(before_json, after_json)
    before = flatten(JSON.parse(before_json))
    after = flatten(JSON.parse(after_json))
    before.any? do |key, value|
      value.is_a?(String) && !value.empty? && !(after[key].is_a?(String) && !after[key].empty?)
    end
  rescue JSON::ParserError
    true
  end

  def persist(shared_home, private_home)
    source = File.join(private_home, AUTH_FILE)
    destination = File.join(shared_home, AUTH_FILE)
    return false unless File.file?(source)

    candidate = File.read(source)
    original = File.file?(destination) ? File.read(destination) : nil
    return false if candidate == original
    raise "refusing to persist malformed refreshed auth" unless valid_auth?(candidate)
    raise "refusing to persist blanked refreshed auth" if original && downgrade?(original, candidate)

    temporary = File.join(shared_home, ".auth.json.refresh-#{Process.pid}-#{SecureRandom.hex(4)}")
    File.write(temporary, candidate, mode: "w", perm: 0o600)
    File.rename(temporary, destination)
    true
  ensure
    FileUtils.rm_f(temporary) if defined?(temporary) && temporary
  end

  def run(shared_home, private_home, command)
    seed(shared_home, private_home)
    ENV["CODEX_HOME"] = private_home
    success = system(*command)
    process_status = $?.exitstatus || 1
    begin
      persist(shared_home, private_home)
    rescue StandardError => error
      warn "Could not safely persist refreshed Codex login: #{error.class}"
      return 75
    end
    success ? process_status : (process_status.zero? ? 1 : process_status)
  end

  def valid_auth?(json)
    parsed = JSON.parse(json)
    parsed.is_a?(Hash) && !flatten(parsed).empty?
  rescue JSON::ParserError
    false
  end

  def flatten(hash, prefix = nil, result = {})
    hash.each do |key, value|
      path = [prefix, key].compact.join(".")
      if value.is_a?(Hash)
        flatten(value, path, result)
      else
        result[path] = value
      end
    end
    result
  end
end

if $PROGRAM_NAME == __FILE__
  shared_home, private_home, *command = ARGV
  abort "usage: auth_runner.rb SHARED_CODEX_HOME PRIVATE_CODEX_HOME COMMAND..." unless shared_home && private_home && !command.empty?
  exit CodexTrialAuth.run(shared_home, private_home, command)
end
