#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "harness"
abort "usage: ruby scripts/restore.rb TRIAL_DIR DESTINATION [baseline|final]" unless (2..3).cover?(ARGV.length)
version = ARGV[2] || "final"
begin
  Pilot.restore(File.expand_path(ARGV[0]), File.expand_path(ARGV[1]), version: version)
  puts "Restored #{version} to #{File.expand_path(ARGV[1])}"
rescue StandardError => e
  warn e.message
  exit 1
end
