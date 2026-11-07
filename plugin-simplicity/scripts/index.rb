#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "pathname"
abort "usage: ruby scripts/index.rb RESULTS_DIR" unless ARGV.size == 1
root = File.expand_path(ARGV.first)
abort "results directory missing" unless Dir.exist?(root)
puts %w[path task agent condition track status restoration_verified].join("\t")
Dir.glob(File.join(root, "**", "meta.json")).sort.each do |path|
  meta = JSON.parse(File.read(path))
  relative = Pathname.new(File.dirname(path)).relative_path_from(Pathname.new(root)).to_s
  puts [relative, *%w[task agent condition track status restoration_verified].map { |key| meta[key] }].map(&:to_s).join("\t")
rescue JSON::ParserError
  warn "invalid metadata: #{path}"
end
