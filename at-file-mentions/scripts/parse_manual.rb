#!/usr/bin/env ruby
# frozen_string_literal: true

# Reads the session a TUI wrote during a manual trial.
#
#   ruby at-file-mentions/scripts/parse_manual.rb results-manual/campfire-01/claude/at_noline/<stamp>
#   ruby at-file-mentions/scripts/parse_manual.rb --all
#
# The interactive clients do not emit the stream-json that parse_transcript.rb
# reads. They append to a session log instead - Claude under
# <config>/projects/<slug>/<uuid>.jsonl, Codex under <config>/sessions/. The
# records carry the same usage fields, so the number this experiment cares
# about, context in the first model request, is still recoverable.
#
# The question this answers: does the TUI resolve @ when `claude -p` does? If it
# attaches, the first request is fat before any tool has run, exactly as in the
# headless probe.

require "json"

EXPERIMENT_DIR = File.expand_path("..", __dir__)

dirs =
  if ARGV.include?("--all")
    Dir.glob(File.join(EXPERIMENT_DIR, "results-manual", "*", "*", "*", "*"))
  else
    # Accept an absolute path, one relative to the current directory, or one
    # relative to the experiment directory - all three are natural to paste.
    ARGV.reject { |a| a.start_with?("--") }.map do |a|
      [a, File.expand_path(a), File.join(EXPERIMENT_DIR, a)].find { |c| Dir.exist?(c) } || a
    end
  end
abort "usage: parse_manual.rb <manual trial dir> | --all" if dirs.empty?

def usage_of(record)
  record.dig("message", "usage") || record["usage"] ||
    record.dig("payload", "info", "total_token_usage") ||
    record.dig("info", "total_token_usage")
end

def context_of(usage)
  usage["input_tokens"].to_i +
    usage["cache_creation_input_tokens"].to_i +
    usage["cache_read_input_tokens"].to_i +
    usage["cached_input_tokens"].to_i
end

# What the user actually sent. The TUI expands @ before the message is stored,
# so a resolved mention shows up here as attached content rather than as the
# literal "@path" the human typed - which is itself the answer.
# A symbol that appears only in the app's defect file, so finding it in the
# session means the file was there rather than that the model guessed.
NEEDLES = {
  "campfire" => "embedded_ipv4",
  "postcraftstudio" => "api_auth",
  "bookmarks" => "with_session_recovery"
}.freeze

def text_of(payload)
  Array(payload.to_h["content"]).map { |c| c["text"] || c["input_text"] }.compact.join("\n")
end

def user_text(record)
  content = record.dig("message", "content")
  case content
  when String then content
  when Array then content.filter_map { |c| c["text"] || c["content"] }.join("\n")
  end
end

rows = []

dirs.sort.each do |dir|
  meta_path = File.join(dir, "meta.json")
  meta = File.exist?(meta_path) ? JSON.parse(File.read(meta_path)) : {}
  agent = meta["agent"] || (dir.include?("/codex/") ? "codex" : "claude")

  pattern = agent == "claude" ? "config/**/projects/**/*.jsonl" : "config/**/sessions/**/*.jsonl"
  files = Dir.glob(File.join(dir, pattern))
  files = Dir.glob(File.join(dir, "config/**/*.jsonl")) if files.empty?

  if files.empty?
    warn "skip #{dir}: no session jsonl under config/"
    next
  end

  # Newest wins if the directory was reused.
  session = files.max_by { |f| File.mtime(f) }
  records = File.readlines(session).filter_map { |l| JSON.parse(l) rescue nil }

  # Codex TUI writes a rollout file, not the item.completed stream `codex exec`
  # emits: session_meta, then response_item envelopes carrying OpenAI-shaped
  # messages. Its first user message is an <environment_context> block, so the
  # pasted prompt is the second.
  rollout = records.any? { |r| r["type"] == "response_item" }

  if rollout
    items = records.select { |r| r["type"] == "response_item" }.map { |r| r["payload"] }
    users = items.select { |p| p["role"] == "user" }
    prompt_item = users.find { |p| !text_of(p).include?("<environment_context>") } || users.last
    text = text_of(prompt_item)
    first_usage = records.filter_map { |r| usage_of(r) }.first
    tool_outputs = items.count { |p| p["type"].to_s.include?("tool_call_output") }
  else
    assistant = records.select { |r| r["type"] == "assistant" || r.dig("message", "role") == "assistant" }
    first_usage = assistant.filter_map { |r| usage_of(r) }.first
    first_user = records.find { |r| r["type"] == "user" || r.dig("message", "role") == "user" }
    text = user_text(first_user.to_h)
    tool_outputs = nil
  end

  # How each client attaches, checked against what it actually writes rather
  # than by a generic ordering rule. A first attempt used "does the file's
  # content appear before the first tool output" and got both agents backwards:
  # Claude's attachment records ARE the mechanism, so counting them as tool
  # output made a real attachment look like a read; and Codex mirrors each tool
  # result into an event_msg one record ahead of the response_item, so a
  # tool-fetched file looked like it arrived early.
  #
  # Claude TUI: an `attachment` record whose attachment.type is "file". The
  # record carries the path and the body, so this is direct evidence.
  # Codex TUI: no attachment record type exists. The mention either expands
  # into the stored user message or it does not, and if the file is only ever
  # seen inside a tool call output then the agent fetched it itself.
  needle = NEEDLES[meta["app"]]

  attached_files = records.select { |r| r["type"] == "attachment" && r.dig("attachment", "type") == "file" }
                          .filter_map { |r| JSON.generate(r)[%r{/workspace/app/[\w./-]+\.\w+}] }

  in_prompt = needle ? text.to_s.include?(needle) : nil
  attached = !attached_files.empty? || in_prompt

  first_hit = needle && records.index { |r| JSON.generate(r).include?(needle) }

  rows << {
    "trial_dir" => dir.sub(EXPERIMENT_DIR + "/", ""),
    "bug_id" => meta["bug_id"],
    "agent" => agent,
    "condition" => meta["condition"],
    "session" => session.sub(dir + "/", ""),
    "records" => records.size,
    "context_before_first_tool_call" => first_usage && context_of(first_usage),
    "first_user_message_chars" => text.to_s.length,
    # A literal "@path" surviving into the stored message means the client did
    # not resolve it. If it resolved, the file content is there instead.
    "at_survived_literally" => text.to_s.include?("@"),
    "mentions_file_content" => text.to_s.length > 2000,
    "attached" => attached,
    "attached_files" => attached_files,
    "needle_in_stored_prompt" => in_prompt,
    "needle_first_seen_at" => first_hit,
    "tool_outputs" => tool_outputs
  }

  File.write(File.join(dir, "manual_metrics.json"), JSON.pretty_generate(rows.last))
end

puts format("%-14s %-7s %-11s %-8s %-9s %-8s %s",
            "bug", "agent", "cond", "ctx1st", "@ literal", "needle@", "verdict")
rows.each do |r|
  verdict =
    if !Array(r["attached_files"]).empty?
      "ATTACHED #{Array(r['attached_files']).size} file(s) as attachment records"
    elsif r["needle_in_stored_prompt"]
      "ATTACHED - file body inlined in the stored prompt"
    elsif r["needle_first_seen_at"]
      "not attached - file first seen at record #{r['needle_first_seen_at']}, via a tool"
    else
      "not attached - file never appears"
    end
  puts format("%-14s %-7s %-11s %-8s %-9s %-8s %s",
              r["bug_id"], r["agent"], r["condition"],
              r["context_before_first_tool_call"] || "-",
              r["at_survived_literally"], r["needle_first_seen_at"] || "-", verdict)
end

puts
puts "  ctx1st is context in the first model request, the same number the"
puts "  headless probe reports. Compare against probe_mention.rb for this app:"
puts "  if the TUI resolves @, ctx1st should sit above the no-mention baseline"
puts "  by roughly the file's token count."
