#!/usr/bin/env ruby
# frozen_string_literal: true

# Turns a trial's raw JSONL transcript into events.jsonl plus metrics.json.
#
#   ruby convention-navigation/scripts/parse_transcript.rb <trial dir>
#   ruby convention-navigation/scripts/parse_transcript.rb --all
#
# The headline number is total input tokens on a trial that passed. The
# mechanism numbers are the ones that say WHY, and they are the reason this file
# is not just a token counter:
#
#   search_calls                     how much hunting it took
#   distinct_files_read              how much of the tree it had to open
#   tool_calls_to_first_target_read  how long until it arrived
#   zero_search_navigation           whether it went straight there
#
# zero_search_navigation is the sharpest of the four. It asks whether the agent
# reached a file it needed without a single grep, glob or find beforehand --
# which is what "the model already knows where to look" means, stated in a way
# that a transcript can answer yes or no. If convention knowledge is worth
# anything, that flag is common on the conventional side and rare on the
# scrambled one, and it says so without depending on token accounting.

require "json"
require "fileutils"
require_relative "../../containers/scripts/lib/kit"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
TASKS = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "tasks.yml"))["tasks"]

# meta.json is the source of truth for targets, because it records what the
# trial actually ran with. tasks.yml is the fallback for a trial recorded before
# the runner persisted them.
def targets_for(meta)
  return Array(meta["targets"]) if meta["targets"].is_a?(Array) && meta["targets"].any?

  task = TASKS.find { |t| t["id"] == meta["task"] } || {}
  Array(task["targets_#{meta['variant']}"])
end

# Shell commands that are hunting rather than reading. Deliberately generous
# about what counts as a search: undercounting search would flatter the
# scrambled condition, which is the direction this experiment must not be wrong
# in.
SEARCH_SHELL = /\b(?:grep|rg|ag|ack|find|fd|glob|locate|tree)\b|\bls\b/
READ_SHELL = /\b(?:cat|head|tail|less|more|bat|nl)\b|\bsed\s+-n\b/

CLAUDE_SEARCH_TOOLS = %w[Grep Glob LS].freeze
CLAUDE_READ_TOOLS = %w[Read NotebookRead].freeze
CLAUDE_EDIT_TOOLS = %w[Edit Write MultiEdit NotebookEdit].freeze

def classify_claude(name, blob)
  return "search" if CLAUDE_SEARCH_TOOLS.include?(name)
  return "read" if CLAUDE_READ_TOOLS.include?(name)
  return "edit" if CLAUDE_EDIT_TOOLS.include?(name)

  if name == "Bash"
    return "search" if blob.match?(SEARCH_SHELL)
    return "read" if blob.match?(READ_SHELL)

    return "bash"
  end
  "other"
end

CODEX_EDIT_ITEMS = %w[file_change patch_apply].freeze

def classify_codex(item_type, command)
  return "edit" if CODEX_EDIT_ITEMS.include?(item_type)
  return "other" unless item_type == "command_execution"
  return "edit" if command.match?(/\bapply_patch\b/)
  return "search" if command.match?(SEARCH_SHELL)
  return "read" if command.match?(READ_SHELL)

  "bash"
end

def paths_in(text)
  text.to_s.scan(%r{[\w./-]+\.(?:rb|erb|yml|yaml|json|md)}).uniq
end

# Where in the call sequence the agent first touched a file it needed.
#
# Matched on the full relative path, never the basename: a basename would also
# fire on an unrelated grep for a common word, and the question is when the
# agent ARRIVED, not when it mentioned something similarly named.
#
# Matched on the LOCATOR -- what the agent asked for -- and never on what came
# back. Codex's event carries the command's aggregated output, so searching the
# whole event counted a `rg` that merely PRINTED the path as the moment the
# agent reached the file. The first real trial run through this parser scored
# exactly that way: one grep, one read, and a verdict of "went straight there
# with no search". The error flatters the scrambled condition, which is the
# direction this experiment least affords to be wrong in, because it dresses a
# successful search up as prediction.
def first_target_index(calls, targets)
  calls.index { |c| targets.any? { |t| c["locator"].include?(t) } }
end

def summarize(calls, turns, targets)
  by_class = calls.group_by { |c| c["class"] }.transform_values(&:size)
  first_target = first_target_index(calls, targets)
  first_edit = calls.index { |c| c["class"] == "edit" }

  searches_before_target =
    first_target ? calls.first(first_target).count { |c| c["class"] == "search" } : nil

  read_paths = calls.select { |c| %w[read edit].include?(c["class"]) }
                    .flat_map { |c| c["paths"] }.uniq

  {
    "total_tool_calls" => calls.size,
    "search_calls" => by_class["search"].to_i,
    "read_calls" => by_class["read"].to_i,
    "edit_calls" => by_class["edit"].to_i,
    "bash_calls" => by_class["bash"].to_i,
    "other_calls" => by_class["other"].to_i,
    "distinct_files_read" => read_paths.size,
    "tool_calls_to_first_target_read" => first_target,
    "tool_calls_to_first_edit" => first_edit,
    "searches_before_first_target" => searches_before_target,
    # nil, not false, when the agent never reached a target: "went straight
    # there" is not a claim you can make about a trial that never arrived, and
    # scoring it false would quietly count failures as evidence against the
    # hypothesis.
    "zero_search_navigation" => first_target.nil? ? nil : searches_before_target.zero?,
    "tool_call_classes" => calls.map { |c| c["class"] },
    "tool_call_names" => calls.map { |c| c["name"] },
    "turns" => turns
  }
end

def summarize_claude(events, meta)
  targets = targets_for(meta)
  init = events.find { |e| e["subtype"] == "init" }
  result = events.reverse.find { |e| e["type"] == "result" }

  turns = []
  calls = []
  events.each do |event|
    next unless event["type"] == "assistant"

    u = event.dig("message", "usage") || {}
    turns << {
      "input_tokens" => u["input_tokens"].to_i,
      "output_tokens" => u["output_tokens"].to_i,
      "cache_creation_input_tokens" => u["cache_creation_input_tokens"].to_i,
      "cache_read_input_tokens" => u["cache_read_input_tokens"].to_i,
      # The three are added rather than chosen between: they are three billing
      # buckets for one prompt, and which bucket a token lands in depends on
      # whether an earlier request warmed the cache. The sum is the context.
      "context_tokens" => u["input_tokens"].to_i + u["cache_creation_input_tokens"].to_i +
                          u["cache_read_input_tokens"].to_i
    }
    Array(event.dig("message", "content")).select { |c| c["type"] == "tool_use" }.each do |use|
      # For Claude the tool input IS the locator: the result comes back in a
      # separate user event, so nothing here can contain a tool's output.
      blob = (use["input"] || {}).to_json
      calls << { "name" => use["name"], "class" => classify_claude(use["name"], blob),
                 "paths" => paths_in(blob), "locator" => blob, "blob" => blob }
    end
  end

  usage = result&.dig("usage") || {}
  summarize(calls, turns, targets).merge(
    "agent" => "claude",
    "model_reported" => init&.dig("model"),
    "cli_version" => init&.dig("claude_code_version"),
    # Hermeticity: a clean container reports none of these.
    "mcp_servers" => init&.dig("mcp_servers") || [],
    "memory_paths" => init&.dig("memory_paths") || {},
    "tools_available" => (init&.dig("tools") || []).size,
    "num_turns" => result&.dig("num_turns"),
    "duration_ms" => result&.dig("duration_ms"),
    "total_cost_usd" => result&.dig("total_cost_usd"),
    "is_error" => result&.dig("is_error"),
    "input_tokens" => usage["input_tokens"],
    "output_tokens" => usage["output_tokens"],
    "cache_creation_input_tokens" => usage["cache_creation_input_tokens"],
    "cache_read_input_tokens" => usage["cache_read_input_tokens"],
    "total_input_tokens" => usage["input_tokens"].to_i +
                            usage["cache_creation_input_tokens"].to_i +
                            usage["cache_read_input_tokens"].to_i,
    "context_before_first_tool_call" => turns.first&.dig("context_tokens")
  )
end

def summarize_codex(events, meta)
  targets = targets_for(meta)
  calls = []
  turns = []
  errors = []

  events.each do |event|
    case event["type"]
    when "item.completed"
      item = event["item"] || {}
      errors << item["message"] if item["type"] == "error"

      command = Array(item["command"]).join(" ")
      klass = classify_codex(item["type"], command)
      next if klass == "other" && !%w[mcp_tool_call web_search].include?(item["type"])

      paths = paths_in(command)
      paths |= Array(item["changes"]).flat_map { |c| c.is_a?(Hash) ? c.keys : [c.to_s] } if item["changes"]
      # The locator is what the agent asked for. item.to_json would also carry
      # aggregated_output, which is what the command printed back -- see the
      # note on first_target_index for what counting that did to the numbers.
      calls << { "name" => item["type"], "class" => klass, "paths" => paths,
                 "locator" => ([command] + paths).join(" "), "blob" => item.to_json }
    when "turn.completed"
      u = event["usage"] || {}
      turns << {
        # Codex INCLUDES cached tokens in input_tokens; cached_input_tokens is a
        # subset reported for information. Adding them would double-count. See
        # startup-context/README.md, where reading this wrong split every
        # measurement into two clusters 35% apart.
        "input_tokens" => u["input_tokens"].to_i,
        "output_tokens" => u["output_tokens"].to_i,
        "cache_read_input_tokens" => u["cached_input_tokens"].to_i,
        "reasoning_output_tokens" => u["reasoning_output_tokens"].to_i,
        "context_tokens" => u["input_tokens"].to_i
      }
    end
  end

  summarize(calls, turns, targets).merge(
    "agent" => "codex",
    "input_tokens" => turns.sum { |t| t["input_tokens"] },
    "output_tokens" => turns.sum { |t| t["output_tokens"] },
    "cache_read_input_tokens" => turns.sum { |t| t["cache_read_input_tokens"] },
    "thinking_tokens" => turns.sum { |t| t["reasoning_output_tokens"] },
    "total_input_tokens" => turns.sum { |t| t["input_tokens"] },
    # Codex reports usage per TURN and a turn contains all of its tool calls, so
    # there is no "before the first tool call" figure to read. Left nil rather
    # than filled with a number that does not mean what the column says.
    "context_before_first_tool_call" => turns.size > 1 ? turns.first["context_tokens"] : nil,
    "codex_errors" => errors
  )
end

def detect_agent(events)
  return "claude" if events.any? { |e| e["type"] == "system" && e["subtype"] == "init" }
  return "codex" if events.any? { |e| e["type"].to_s.start_with?("item.", "turn.", "thread.") }

  "unknown"
end

paths =
  if ARGV.include?("--all")
    Dir.glob(File.join(EXPERIMENT_DIR, "results-raw", "**", "transcript.jsonl")).map { |p| File.dirname(p) }
  else
    ARGV.reject { |a| a.start_with?("--") }
  end
abort "usage: parse_transcript.rb <trial dir> | --all" if paths.empty?

rows = []
skipped = 0

paths.sort.each do |dir|
  transcript = File.join(dir, "transcript.jsonl")
  unless File.exist?(transcript)
    warn "skip #{dir}: no transcript.jsonl"
    next
  end

  meta_path = File.join(dir, "meta.json")
  meta = File.exist?(meta_path) ? JSON.parse(File.read(meta_path)) : {}

  # A trial that died before the agent got a turn has no data in it. Parsed
  # anyway it becomes a row of zeros that looks like an agent which did nothing
  # -- which is a very different claim, and one that would be averaged in.
  if meta["aborted"]
    warn "skip #{dir.sub(EXPERIMENT_DIR + '/', '')}: aborted (#{meta['aborted']})"
    skipped += 1
    next
  end

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

  acceptance_path = File.join(dir, "acceptance.json")
  acceptance = File.exist?(acceptance_path) ? JSON.parse(File.read(acceptance_path)) : {}

  summary.merge!(
    "unparsable_lines" => bad,
    "raw_events" => events.size,
    "task" => meta["task"],
    "app" => meta["app"],
    "condition" => meta["condition"],
    "variant" => meta["variant"],
    "targets" => targets_for(meta),
    "passed" => meta["passed"],
    "acceptance_facts" => acceptance["facts"],
    "wall_seconds" => meta["wall_seconds"],
    "timed_out" => meta["timed_out"],
    "map_bytes" => meta["map_bytes"],
    "changed_files" => meta["changed_files"],
    "trial_dir" => dir.sub(EXPERIMENT_DIR + "/", "")
  )

  File.write(File.join(dir, "events.jsonl"), events.map(&:to_json).join("\n") + "\n")
  File.write(File.join(dir, "metrics.json"), JSON.pretty_generate(summary))
  rows << summary
end

puts "\n#{rows.size} trial(s) parsed#{skipped.positive? ? ", #{skipped} aborted and skipped" : ''}\n\n"
puts format("%-24s %-7s %-17s %6s %6s %6s %8s %8s %6s %6s",
            "task", "agent", "condition", "tools", "srch", "files", "in_tok", "out_tok", "0srch", "pass")
rows.each do |r|
  puts format("%-24s %-7s %-17s %6s %6s %6s %8s %8s %6s %6s",
              r["task"], r["agent"], r["condition"], r["total_tool_calls"], r["search_calls"],
              r["distinct_files_read"], r["total_input_tokens"], r["output_tokens"],
              r["zero_search_navigation"].inspect[0, 5], r["passed"].inspect[0, 5])
end

# A trial is contaminated when it can reach state that outlives it or is shared
# with another trial. The CLI always reports an auto-memory path, so the question
# is not whether one exists but where it points: inside the per-trial config
# directory it dies with the container; under the mounted credential store it is
# the same directory for every trial. Testing for existence rather than location
# flags every clean run, which trains you to ignore the warning that matters.
SHARED_MOUNT = "/home/agent/.agent-auth"

flagged = rows.select { |r| r["agent"] == "claude" }.filter_map do |row|
  reasons = []
  servers = Array(row["mcp_servers"])
  unless servers.empty?
    reasons << "mcp servers attached: #{servers.map { |s| s.is_a?(Hash) ? s['name'] : s }.join(', ')}"
  end
  Hash(row["memory_paths"]).each do |kind, path|
    reasons << "#{kind} memory lives in the shared mount: #{path}" if path.to_s.start_with?(SHARED_MOUNT)
  end
  reasons.empty? ? nil : [row, reasons]
end

unless flagged.empty?
  warn "\nWARNING: #{flagged.size} trial(s) ran with state they should not have had:"
  flagged.each do |(row, reasons)|
    warn "  #{row['trial_dir']}"
    reasons.each { |reason| warn "    - #{reason}" }
  end
end
