#!/usr/bin/env ruby
# frozen_string_literal: true

# Turns a trial's raw JSONL transcript into events.jsonl plus a metrics summary.
#
#   ruby at-file-mentions/scripts/parse_transcript.rb <trial dir>
#   ruby at-file-mentions/scripts/parse_transcript.rb --all
#
# The headline number this experiment is after is context growth BEFORE the
# first tool call. If `@path` makes a CLI attach the file itself, the first
# request carries the file's tokens and no read is needed to get them; if `@` is
# inert text, the first request looks like the bare one and the file arrives
# later through a normal read. Those two shapes are distinguishable here, which
# is why per-turn token counts are kept rather than only the totals.

require "json"
require "fileutils"
require_relative "../../containers/scripts/lib/kit"

EXPERIMENT_DIR = File.expand_path("..", __dir__)

# bugs.yml is the fallback for impl_files/test_file. A trial recorded before
# the runner persisted them has neither in meta.json, and matching against an
# empty list makes tool_calls_to_first_defect_read nil for every row.
BUGS = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]

def ground_truth(meta)
  bug = BUGS.find { |b| b["id"] == meta["bug_id"] } || {}
  [Array(meta["impl_files"] || bug["impl_files"]), meta["test_file"] || bug["test_file"]]
end

paths =
  if ARGV.include?("--all")
    Dir.glob(File.join(EXPERIMENT_DIR, "results-raw", "**", "transcript.jsonl")).map { |p| File.dirname(p) }
  else
    ARGV.reject { |a| a.start_with?("--") }
  end
abort "usage: parse_transcript.rb <trial dir> | --all" if paths.empty?

# Claude emits stream-json; Codex emits its own JSONL. Detect rather than
# configure, so a transcript can be parsed without knowing who produced it.
def detect_agent(events)
  return "claude" if events.any? { |e| e["type"] == "system" && e["subtype"] == "init" }
  return "codex" if events.any? { |e| e["type"].to_s.start_with?("item.", "turn.", "thread.") }

  "unknown"
end

def usage_of(event)
  event.dig("message", "usage") || event["usage"]
end

def tool_uses_in(event)
  content = event.dig("message", "content")
  return [] unless content.is_a?(Array)

  content.select { |c| c["type"] == "tool_use" }
end

# Which file a tool call touched, when it is knowable. Reads, edits and writes
# name a path directly; a shell command has to be scanned for one.
def paths_in_tool_use(use)
  input = use["input"] || {}
  direct = [input["file_path"], input["path"], input["notebook_path"]].compact
  return direct unless direct.empty?

  text = [input["command"], input["pattern"], input["prompt"]].compact.join(" ")
  text.scan(%r{[\w./-]+\.(?:rb|erb|yml|yaml)}).uniq
end

# Does this tool call refer to the defect file?
#
# Matching on the full relative path rather than the basename: a basename would
# also fire on an unrelated grep for a common word, and the point of the metric
# is how many calls it took to arrive at the file, not how many mentioned a
# similar-sounding name. The whole serialised input is searched, so a Read with
# a file_path and a shell `cat <path>` both count.
def references_impl?(blob, impl_files)
  impl_files.any? { |f| blob.include?(f) }
end

def summarize_claude(events, meta)
  impl, test_file = ground_truth(meta)

  init = events.find { |e| e["subtype"] == "init" }
  result = events.reverse.find { |e| e["type"] == "result" }

  turns = []
  tool_calls = []
  events.each do |event|
    next unless event["type"] == "assistant"

    u = usage_of(event) || {}
    turns << {
      "input_tokens" => u["input_tokens"].to_i,
      "output_tokens" => u["output_tokens"].to_i,
      "cache_creation_input_tokens" => u["cache_creation_input_tokens"].to_i,
      "cache_read_input_tokens" => u["cache_read_input_tokens"].to_i,
      "context_tokens" => u["input_tokens"].to_i +
                          u["cache_creation_input_tokens"].to_i +
                          u["cache_read_input_tokens"].to_i,
      "tool_calls" => tool_uses_in(event).map { |t| t["name"] }
    }
    tool_uses_in(event).each do |use|
      tool_calls << { "name" => use["name"], "paths" => paths_in_tool_use(use),
                      "blob" => (use["input"] || {}).to_json }
    end
  end

  first_defect_read = tool_calls.index { |t| references_impl?(t["blob"], impl) }
  first_edit = tool_calls.index { |t| %w[Edit Write NotebookEdit MultiEdit].include?(t["name"]) }

  usage = result&.dig("usage") || {}

  {
    "agent" => "claude",
    "model_reported" => init&.dig("model"),
    "cli_version" => init&.dig("claude_code_version"),
    # Hermeticity: a clean container should report none of these. If any is
    # non-empty the trial ran with help it was not supposed to have.
    "mcp_servers" => init&.dig("mcp_servers") || [],
    "memory_paths" => init&.dig("memory_paths") || {},
    "tools_available" => (init&.dig("tools") || []).size,
    "num_turns" => result&.dig("num_turns"),
    "duration_ms" => result&.dig("duration_ms"),
    "duration_api_ms" => result&.dig("duration_api_ms"),
    "total_cost_usd" => result&.dig("total_cost_usd"),
    "stop_reason" => result&.dig("stop_reason"),
    "is_error" => result&.dig("is_error"),
    "input_tokens" => usage["input_tokens"],
    "output_tokens" => usage["output_tokens"],
    "cache_creation_input_tokens" => usage["cache_creation_input_tokens"],
    "cache_read_input_tokens" => usage["cache_read_input_tokens"],
    "thinking_tokens" => usage.dig("output_tokens_details", "thinking_tokens"),
    "total_tool_calls" => tool_calls.size,
    "tool_call_names" => tool_calls.map { |t| t["name"] },
    "tool_calls_to_first_defect_read" => first_defect_read,
    "tool_calls_to_first_edit" => first_edit,
    "read_before_edit" => first_defect_read && first_edit ? first_defect_read < first_edit : nil,
    # The auto-attachment signature: how much context the very first request
    # carried, before any tool could have fetched anything.
    "context_before_first_tool_call" => turns.first&.dig("context_tokens"),
    "turns" => turns,
    "test_file" => test_file
  }
end

# Codex emits `item.completed` envelopes and one `turn.completed` carrying usage.
# Item types seen in practice: command_execution (command, aggregated_output,
# exit_code, status), file_change, agent_message, reasoning, error.
#
# One asymmetry to be honest about: Codex reports tokens per TURN, and a turn
# contains all of its tool calls. So the context carried before the first tool
# call - the auto-attachment signature this experiment is chasing - is directly
# observable for Claude and not for Codex. For Codex the same effect can only
# show up in the totals, which is weaker but not nothing. It is left nil rather
# than filled with a number that does not mean what the column says.
CODEX_EDIT_ITEMS = %w[file_change patch_apply].freeze
CODEX_TOOL_ITEMS = (CODEX_EDIT_ITEMS + %w[command_execution mcp_tool_call web_search]).freeze

def summarize_codex(events, meta)
  impl, = ground_truth(meta)

  tool_calls = []
  turns = []
  errors = []

  events.each do |event|
    case event["type"]
    when "item.completed"
      item = event["item"] || {}
      errors << item["message"] if item["type"] == "error"
      next unless CODEX_TOOL_ITEMS.include?(item["type"])

      command = Array(item["command"]).join(" ")
      paths = command.scan(%r{[\w./-]+\.(?:rb|erb|yml|yaml)}).uniq
      paths |= Array(item["changes"]).flat_map { |c| c.is_a?(Hash) ? c.keys : [c.to_s] } if item["changes"]

      tool_calls << { "name" => item["type"], "paths" => paths, "command" => command,
                      "exit_code" => item["exit_code"], "blob" => item.to_json }
    when "turn.completed"
      u = event["usage"] || {}
      turns << {
        "input_tokens" => u["input_tokens"].to_i,
        "output_tokens" => u["output_tokens"].to_i,
        "cache_read_input_tokens" => u["cached_input_tokens"].to_i,
        "cache_creation_input_tokens" => u["cache_write_input_tokens"].to_i,
        "reasoning_output_tokens" => u["reasoning_output_tokens"].to_i,
        "context_tokens" => u["input_tokens"].to_i
      }
    end
  end

  first_defect_read = tool_calls.index { |t| references_impl?(t["blob"], impl) }
  first_edit = tool_calls.index { |t| CODEX_EDIT_ITEMS.include?(t["name"]) }

  {
    "agent" => "codex",
    "input_tokens" => turns.sum { |t| t["input_tokens"] },
    "output_tokens" => turns.sum { |t| t["output_tokens"] },
    "cache_read_input_tokens" => turns.sum { |t| t["cache_read_input_tokens"] },
    "cache_creation_input_tokens" => turns.sum { |t| t["cache_creation_input_tokens"] },
    "thinking_tokens" => turns.sum { |t| t["reasoning_output_tokens"] },
    "total_tool_calls" => tool_calls.size,
    "tool_call_names" => tool_calls.map { |t| t["name"] },
    "tool_calls_to_first_defect_read" => first_defect_read,
    "tool_calls_to_first_edit" => first_edit,
    "read_before_edit" => first_defect_read && first_edit ? first_defect_read < first_edit : nil,
    # Only meaningful if Codex ever reports more than one turn; see the note above.
    "context_before_first_tool_call" => turns.size > 1 ? turns.first["context_tokens"] : nil,
    "codex_errors" => errors,
    "turns" => turns
  }
end

rows = []

paths.each do |dir|
  transcript = File.join(dir, "transcript.jsonl")
  unless File.exist?(transcript)
    warn "skip #{dir}: no transcript.jsonl"
    next
  end

  meta_path = File.join(dir, "meta.json")
  meta = File.exist?(meta_path) ? JSON.parse(File.read(meta_path)) : {}

  bad = 0
  events = File.readlines(transcript).filter_map do |line|
    JSON.parse(line)
  rescue JSON::ParserError
    bad += 1
    nil
  end

  agent = meta["agent"] || detect_agent(events)
  summary =
    case agent
    when "claude" then summarize_claude(events, meta)
    when "codex" then summarize_codex(events, meta)
    else { "agent" => "unknown", "events" => events.size }
    end

  summary["unparsable_lines"] = bad
  summary["raw_events"] = events.size
  summary["bug_id"] = meta["bug_id"]
  summary["condition"] = meta["condition"]
  summary["app"] = meta["app"]
  summary["fix_verified"] = meta["fix_verified"]
  summary["wall_seconds"] = meta["wall_seconds"]
  summary["timed_out"] = meta["timed_out"]
  summary["bug_reproduces"] = meta["bug_reproduces"]
  summary["trial_dir"] = dir.sub(EXPERIMENT_DIR + "/", "")

  File.write(File.join(dir, "events.jsonl"), events.map(&:to_json).join("\n") + "\n")
  File.write(File.join(dir, "metrics.json"), JSON.pretty_generate(summary))
  rows << summary
end

puts format("%-18s %-8s %-6s %6s %8s %7s %7s %6s",
            "bug", "agent", "cond", "tools", "ctx1st", "out", "wall", "fixed")
rows.each do |r|
  puts format("%-18s %-8s %-6s %6s %8s %7s %7s %6s",
              r["bug_id"], r["agent"], r["condition"],
              r["total_tool_calls"], r["context_before_first_tool_call"],
              r["output_tokens"], r["wall_seconds"], r["fix_verified"])
end

# A trial is contaminated when it can reach state that outlives it or is shared
# with another trial. The CLI always reports an auto-memory path, so the
# question is not whether one exists -- it always does -- but where it points.
# Inside the per-trial config directory it dies with the container. Under the
# mounted credential store it is the same directory for every trial, and what
# one trial could leave there is the location of the defect. Testing for
# existence rather than location flags every clean run, which trains you to
# ignore the warning that matters.
SHARED_MOUNT = "/home/agent/.agent-auth"

def contamination(row)
  reasons = []

  servers = Array(row["mcp_servers"])
  unless servers.empty?
    names = servers.map { |s| s.is_a?(Hash) ? s["name"] : s }
    reasons << "mcp servers attached: #{names.join(', ')}"
  end

  Hash(row["memory_paths"]).each do |kind, path|
    reasons << "#{kind} memory lives in the shared mount: #{path}" if path.to_s.start_with?(SHARED_MOUNT)
  end

  reasons
end

flagged = rows.select { |r| r["agent"] == "claude" }
              .map { |r| [r, contamination(r)] }
              .reject { |(_, reasons)| reasons.empty? }

unless flagged.empty?
  warn "\nWARNING: #{flagged.size} trial(s) ran with state they should not have had:"
  flagged.each do |(row, reasons)|
    warn "  #{row['trial_dir']}"
    reasons.each { |reason| warn "    - #{reason}" }
  end
end
