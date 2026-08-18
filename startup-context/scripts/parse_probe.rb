#!/usr/bin/env ruby
# frozen_string_literal: true

# Turns raw probe output into per-run metrics.json plus one summary.json.
#
#   ruby startup-context/scripts/parse_probe.rb
#   ruby startup-context/scripts/parse_probe.rb --dir results-raw/claude/host-full/2026...
#
# The headline number is `startup_context_tokens`: everything the model was sent
# before it produced its first token. For Claude that is the first assistant
# turn's input_tokens + cache_creation_input_tokens + cache_read_input_tokens.
# The three are added rather than picked between because they are three billing
# buckets for one prompt, and which bucket a token lands in depends on whether
# an earlier run happened to warm the cache. The sum does not move; the price
# does, which is why cost is reported but never compared.
#
# Codex reports usage once per turn and this probe is one turn, so its
# input_tokens is the same quantity by a different route.
#
# A run is only valid if the agent answered from the prompt alone. Any tool call
# means the measurement includes work, not just startup, and the row is flagged.

require "fileutils"
require "json"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
RAW = File.join(EXPERIMENT_DIR, "results-raw")

dirs =
  if (i = ARGV.index("--dir"))
    [File.expand_path(ARGV[i + 1], EXPERIMENT_DIR)]
  else
    # meta.json is written last, so a directory without one is a run still in
    # flight or a run that died. Either way there is nothing to measure yet.
    Dir.glob(File.join(RAW, "*", "*", "*"))
       .select { |d| File.directory?(d) && File.exist?(File.join(d, "meta.json")) }
       .sort
  end
abort "no probe runs under #{RAW}" if dirs.empty?

def read_events(path)
  return [] unless File.exist?(path)

  File.readlines(path).filter_map do |line|
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end
end

# MCP servers are counted by status as well as in total, because a server that
# failed or needs auth is not free: it was still started, waited for, and in
# several cases still contributes tool stubs.
def mcp_breakdown(servers)
  by_status = Hash.new(0)
  Array(servers).each { |s| by_status[(s.is_a?(Hash) ? s["status"] : "unknown").to_s] += 1 }
  by_status
end

def summarize_claude(events)
  init = events.find { |e| e["subtype"] == "init" } || {}
  first_assistant = events.find { |e| e["type"] == "assistant" }
  result = events.reverse.find { |e| e["type"] == "result" } || {}

  usage = first_assistant&.dig("message", "usage") || {}
  startup = usage["input_tokens"].to_i +
            usage["cache_creation_input_tokens"].to_i +
            usage["cache_read_input_tokens"].to_i

  tool_calls = events.select { |e| e["type"] == "assistant" }.flat_map do |e|
    Array(e.dig("message", "content")).select { |c| c.is_a?(Hash) && c["type"] == "tool_use" }
  end

  {
    "cli_version" => init["claude_code_version"],
    "model_reported" => init["model"],
    "startup_context_tokens" => startup,
    "output_tokens" => usage["output_tokens"].to_i,
    "cost_usd" => result["total_cost_usd"],
    "num_turns" => result["num_turns"],
    "answer" => result["result"],
    "tool_calls" => tool_calls.map { |t| t["name"] },
    "tools_available" => Array(init["tools"]).size,
    "mcp_servers" => Array(init["mcp_servers"]).size,
    "mcp_by_status" => mcp_breakdown(init["mcp_servers"]),
    "skills" => Array(init["skills"]).size,
    "slash_commands" => Array(init["slash_commands"]).size,
    "subagents" => Array(init["agents"]).size,
    "plugins" => Array(init["plugins"]).size,
"hooks_fired" => events.count { |e| e["subtype"] == "hook_started" },
# A SessionStart hook's stdout is prepended to the conversation, so its size
# is context the user paid for without asking for it. Measured here rather
# than inferred, because it is the one layer with no flag to turn it off
# short of --safe-mode.
"hook_injected_bytes" => events.select { |e| e["subtype"] == "hook_response" }
                               .sum { |e| e["output"].to_s.bytesize },
    "memory_paths" => init["memory_paths"] || {},
    "output_style" => init["output_style"]
  }
end

def summarize_codex(events)
  turn = events.find { |e| e["type"] == "turn.completed" } || {}
  usage = turn["usage"] || {}
  items = events.select { |e| e["type"] == "item.completed" }.map { |e| e["item"] || {} }

  answer = items.find { |it| it["type"] == "agent_message" }
  tool_items = items.select { |it| %w[command_execution file_change patch_apply mcp_tool_call web_search].include?(it["type"]) }

  {
    "cli_version" => nil,
    "model_reported" => nil,
    # Codex reports the whole turn's input in one number and this probe is a
    # single turn with no tool calls, so the turn's input IS the startup context.
    "startup_context_tokens" => usage["input_tokens"].to_i,
    "output_tokens" => usage["output_tokens"].to_i,
    "reasoning_tokens" => usage["reasoning_output_tokens"].to_i,
    "cost_usd" => nil,
    "num_turns" => events.count { |e| e["type"] == "turn.completed" },
    "answer" => answer && answer["text"],
    "tool_calls" => tool_items.map { |it| it["type"] },
    # Codex has no init event, so its loaded surface is not observable from the
    # transcript. inventory.rb reads it off disk instead. What the transcript
    # does carry are the CLI's own warnings, and those turned out to matter.
    "cli_notices" => items.select { |it| it["type"] == "error" }.map { |it| it["message"] }
  }
end

rows = dirs.map do |dir|
  meta = JSON.parse(File.read(File.join(dir, "meta.json")))
  events = read_events(File.join(dir, "transcript.jsonl"))
  summary = meta["agent"] == "claude" ? summarize_claude(events) : summarize_codex(events)

  version_file = File.join(dir, "agent-version.txt")
  summary["cli_version"] ||= File.read(version_file).strip if File.exist?(version_file)

  row = meta.merge(summary)
  row["raw_events"] = events.size
  row["clean_probe"] = summary["tool_calls"].empty? && summary["startup_context_tokens"].to_i.positive?
  row["run_dir"] = dir.sub(EXPERIMENT_DIR + "/", "")
  File.write(File.join(dir, "metrics.json"), JSON.pretty_generate(row))
  row
end

File.write(File.join(EXPERIMENT_DIR, "results-raw", "summary.json"), JSON.pretty_generate(rows))

puts format("%-7s %-15s %2s %9s %6s %5s %5s %6s %6s %7s %5s",
            "agent", "condition", "#", "startup", "tools", "mcp", "skil", "cmds", "agents", "hooks", "ok")
rows.each do |r|
  puts format("%-7s %-15s %2s %9s %6s %5s %5s %6s %6s %7s %5s",
              r["agent"], r["condition"], r["repeat"],
              r["startup_context_tokens"], r["tools_available"] || "-",
              r["mcp_servers"] || "-", r["skills"] || "-",
              r["slash_commands"] || "-", r["subagents"] || "-",
              r["hooks_fired"] || "-", r["clean_probe"] ? "y" : "NO")
end

dirty = rows.reject { |r| r["clean_probe"] }
unless dirty.empty?
  warn "\nWARNING: #{dirty.size} run(s) did not measure startup alone:"
  dirty.each { |r| warn "  #{r['run_dir']} tool_calls=#{r['tool_calls'].inspect} tokens=#{r['startup_context_tokens']}" }
end
