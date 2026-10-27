#!/usr/bin/env ruby
# frozen_string_literal: true

# Scores every captured commit message. Reads runs/<agent>/<arm>.<rep>.txt and
# the matching .json, writes one row per trial.
#
#   ruby measure.rb [agent ...]

require "json"

EXP = File.expand_path("..", __dir__)
RUNS = ENV.fetch("GCC_RUNS", "runs")            # "runs" (host) or "runs-container"
SUFFIX = RUNS == "runs" ? "" : "-container"

CONVENTIONAL = /\A(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([^)]+\))?!?: \S/
ATTRIB_TRAILER = /^(Co-Authored-By|Co-authored-by|Signed-off-by):/i
SESSION_TRAILER = /^(Claude-Session|Session|Codex-Session):/i
AI_WORDS = /\b(claude|codex|opencode|anthropic|openai|copilot|\bAI\b|assistant|generated with)\b/i

def score(message, meta)
  lines = message.split("\n")
  subject = lines.first.to_s
  trailers = lines.select { |l| l =~ ATTRIB_TRAILER || l =~ SESSION_TRAILER }
  body = lines[1..].to_a
             .reject { |l| l =~ ATTRIB_TRAILER || l =~ SESSION_TRAILER }
             .reject { |l| l.strip.empty? }

  {
    "agent" => meta["agent"],
    "arm" => meta["arm"],
    "rep" => meta["rep"],
    "committed" => meta["committed"],
    "seconds" => meta["seconds"],
    "subject" => subject,
    "subject_len" => subject.length,
    "conventional" => !(subject =~ CONVENTIONAL).nil?,
    "body_lines" => body.length,
    "attribution" => trailers.grep(ATTRIB_TRAILER).first,
    "session_trailer" => trailers.grep(SESSION_TRAILER).first,
    "any_attribution" => !trailers.empty?,
    "mentions_ai" => !(message =~ AI_WORDS).nil?,
    "bytes" => message.bytesize
  }
end

agents = ARGV.empty? ? Dir.children(File.join(EXP, RUNS)).sort : ARGV
rows = []
agents.each do |agent|
  dir = File.join(EXP, RUNS, agent)
  next unless Dir.exist?(dir)
  Dir.glob(File.join(dir, "*.json")).sort.each do |meta_path|
    meta = JSON.parse(File.read(meta_path))
    msg_path = meta_path.sub(/\.json\z/, ".txt")
    next unless File.exist?(msg_path)
    rows << score(File.read(msg_path), meta)
  end
end

File.write(File.join(EXP, "METRICS#{SUFFIX}.json"), JSON.pretty_generate(rows))

# Per-arm summary: the reps of one cell should agree, and disagreement is signal.
puts format("%-9s %-30s %-3s %-5s %-4s %-5s %-4s %s",
            "AGENT", "ARM", "CMT", "CONV", "BODY", "ATTR", "SESS", "ATTRIBUTION TEXT")
puts "-" * 118
rows.each do |r|
  puts format("%-9s %-30s %-3s %-5s %-4d %-5s %-4s %s",
              r["agent"], r["arm"],
              r["committed"] ? "y" : "NO",
              r["conventional"] ? "yes" : "no",
              r["body_lines"],
              r["attribution"] ? "yes" : "-",
              r["session_trailer"] ? "yes" : "-",
              (r["attribution"] || "").sub(/\ACo-[Aa]uthored-[Bb]y: /, ""))
end

puts
puts "cells where the two reps disagree on a boolean:"
rows.group_by { |r| [r["agent"], r["arm"]] }.each do |(agent, arm), reps|
  next if reps.size < 2
  %w[conventional any_attribution mentions_ai committed].each do |k|
    vals = reps.map { |r| r[k] }.uniq
    puts "  #{agent}/#{arm}: #{k} = #{vals.inspect}" if vals.size > 1
  end
end
