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

# A heredoc body is data the agent WROTE, not a command it ran. Claude writes
# probe scripts with `cat > /tmp/probe.rb <<'EOF' ... EOF`, and one of those
# scripts contained the word `find`, which scored the whole call as a search.
# Strip the bodies before classifying anything.
def strip_heredocs(command)
  command.to_s.gsub(/<<-?\s*(['"]?)(\w+)\1.*?^\s*\2\s*$/m, "<<HEREDOC")
         .gsub(/<<-?\s*(['"]?)(\w+)\1.*\z/m, "<<HEREDOC")
end

# Claude batches: one Bash call is routinely `ls a && cat b; grep c`. Counting
# that as a single act of anything loses most of what happened, and how much an
# agent batches could easily differ between conditions -- which would show up as
# a fake difference in call counts. So segments are counted as well as calls.
def shell_segments(command)
  strip_heredocs(command).split(/;|&&|\|\||\||\n/).map(&:strip).reject(&:empty?)
end

def classify_shell(segment)
  # A search that pipes its output somewhere is still a search, so this is
  # checked first and the redirect test below never demotes it.
  return "search" if segment.match?(SEARCH_SHELL)

  # `cat > /tmp/probe.rb` is a write dressed as a read: the word `cat` is there,
  # but the agent is creating a file, not navigating to one. Only a redirect
  # into a path counts -- `2>&1` and `>&2` are not writes to look at.
  writes_a_file = segment.match?(/>\s*(?!&)\S/) && !segment.match?(/\A\s*\d?>\s*&/)
  return "bash" if writes_a_file

  return "read" if segment.match?(READ_SHELL)

  "bash"
end

CLAUDE_SEARCH_TOOLS = %w[Grep Glob LS].freeze
CLAUDE_READ_TOOLS = %w[Read NotebookRead].freeze
CLAUDE_EDIT_TOOLS = %w[Edit Write MultiEdit NotebookEdit].freeze

def classify_claude(name, command)
  return "search" if CLAUDE_SEARCH_TOOLS.include?(name)
  return "read" if CLAUDE_READ_TOOLS.include?(name)
  return "edit" if CLAUDE_EDIT_TOOLS.include?(name)
  return "other" unless name == "Bash"

  # Search wins over read in a mixed call, because the question the metric
  # answers is "did the agent have to hunt", and a call that hunted did.
  classes = shell_segments(command).map { |s| classify_shell(s) }
  return "search" if classes.include?("search")
  return "read" if classes.include?("read")

  "bash"
end

# This container's Claude has no Grep, Glob or LS tool -- its `tools` list at
# init carries Bash, Read, Edit and Write but nothing for searching -- so every
# search it performs is a shell command. Both agents therefore navigate through
# the shell here, which is worth knowing when reading the tool counts, though it
# still does not make them poolable.
def segment_counts(command)
  shell_segments(command).map { |s| classify_shell(s) }.tally
end

CODEX_EDIT_ITEMS = %w[file_change patch_apply].freeze

def classify_codex(item_type, command)
  return "edit" if CODEX_EDIT_ITEMS.include?(item_type)
  return "other" unless item_type == "command_execution"
  return "edit" if command.match?(/\bapply_patch\b/)

  classes = shell_segments(command).map { |s| classify_shell(s) }
  return "search" if classes.include?("search")
  return "read" if classes.include?("read")

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

  # Segments as well as calls. A call is one turn of the agent's attention; a
  # segment is one thing it actually asked the machine to do, and Claude
  # routinely puts three or four in a single call. If an agent batches more
  # heavily in one condition than the other -- which is plausible, since more
  # exploration invites more chaining -- call counts alone would show that as a
  # difference in effort when it is a difference in packaging.
  segments = calls.map { |c| c["segments"] || {} }
                  .each_with_object(Hash.new(0)) { |h, acc| h.each { |k, v| acc[k] += v } }

  {
    "total_tool_calls" => calls.size,
    "total_shell_segments" => segments.values.sum,
    "search_segments" => segments["search"].to_i,
    "read_segments" => segments["read"].to_i,
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
      # separate user event, so nothing here can contain a tool's output. The
      # heredoc bodies still come out, so a path mentioned inside a script the
      # agent wrote is not mistaken for the agent opening that path.
      input = use["input"] || {}
      command = input["command"].to_s
      blob = input.to_json
      locator = command.empty? ? blob : strip_heredocs(command) + " " + [input["file_path"], input["path"]].compact.join(" ")
      calls << { "name" => use["name"], "class" => classify_claude(use["name"], command),
                 "paths" => paths_in(locator), "locator" => locator, "blob" => blob,
                 "segments" => command.empty? ? {} : segment_counts(command) }
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

      stripped = strip_heredocs(command)
      paths = paths_in(stripped)
      paths |= Array(item["changes"]).flat_map { |c| c.is_a?(Hash) ? c.keys : [c.to_s] } if item["changes"]
      # The locator is what the agent asked for. item.to_json would also carry
      # aggregated_output, which is what the command printed back -- see the
      # note on first_target_index for what counting that did to the numbers.
      calls << { "name" => item["type"], "class" => klass, "paths" => paths,
                 "locator" => ([stripped] + paths).join(" "), "blob" => item.to_json,
                 "segments" => command.empty? ? {} : segment_counts(command) }
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

# The classifier decides what `search_calls` means, and that is a headline
# number, so it is checked rather than trusted. Every case below is a real
# command taken from a transcript, including the two that were being scored
# wrongly: a probe script whose heredoc body contained the word `find`, and a
# `cat >` that writes a file rather than reading one.
if ARGV.include?("--selftest")
  cases = {
    "cat -n platform/core/entities/room.rb" => "read",
    "grep -rn foo . > /tmp/out" => "search",
    "ls app" => "search",
    "bin/rails runner /tmp/p.rb 2>&1" => "bash",
    "sed -n '1,60p' config/routes.rb" => "read",
    "head -20 Gemfile" => "read",
    "bin/rails test" => "bash"
  }
  failures = []
  cases.each do |command, want|
    got = classify_shell(command)
    puts format("  %-6s %-46s want=%s", got == want ? "ok" : "FAIL", command[0, 46], want)
    failures << command unless got == want
  end

  # Whole-call behaviour: heredoc bodies must not be classified, and a call that
  # both lists and reads counts as a search because the agent still had to hunt.
  probe = "cat > /tmp/probe.rb <<'EOF'\nRoom.find_each do |r|\n  puts r\nend\nEOF"
  compound = "ls delivery/http/handlers/ && cat -n delivery/http/handlers/rooms_controller.rb"
  [[probe, "bash", "heredoc body is not a command"],
   [compound, "search", "a call that lists and reads is a search"]].each do |command, want, why|
    got = classify_claude("Bash", command)
    puts format("  %-6s %-46s want=%s (%s)", got == want ? "ok" : "FAIL", why[0, 46], want, why)
    failures << why unless got == want
  end

  segs = segment_counts(compound)
  ok = segs["search"] == 1 && segs["read"] == 1
  puts format("  %-6s %-46s want=%s", ok ? "ok" : "FAIL", "compound call splits into 1 search + 1 read",
              { "search" => 1, "read" => 1 })
  failures << "segments" unless ok

  puts(failures.empty? ? "\nall self-tests passed" : "\n#{failures.size} self-test(s) FAILED")
  exit(failures.empty? ? 0 : 1)
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
