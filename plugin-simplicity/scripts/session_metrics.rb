#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

# Counts observable transcript events. It does not infer private reasoning,
# human intervention, subagent work, elapsed effort, or cost.
module SessionMetrics
  module_function

  def parse(path, agent:, include_question_text: false)
    raise ArgumentError, "agent must be claude or codex" unless %w[claude codex].include?(agent)
    events = []
    malformed = 0
    File.foreach(path) do |line|
      next if line.strip.empty?
      begin
        event = JSON.parse(line)
        events << event if event.is_a?(Hash)
      rescue JSON::ParserError
        malformed += 1
      end
    end

    calls = []
    skill_evidence = []
    hook_deliveries = []
    questions = []
    timestamps = []
    events.each_with_index do |event, index|
      timestamps << event["timestamp"] || event["time"]
      calls.concat(tool_calls(event, agent).map { |call| call.merge("event_index" => index) })
      skill_evidence.concat(skill_observations(event, agent))
      hook = hook_delivery(event)
      hook_deliveries << hook if hook
      question = assistant_question_text(event, agent)
      questions << question if question
    end
    calls.uniq! { |call| call["id"] ? [call["name"], call["id"]] : [call["name"], call["event_index"]] }
    timestamps = timestamps.compact.filter_map { |value| parse_time(value) }.sort

    {"source" => File.basename(path), "agent" => agent,
     "tool_call_count" => calls.length,
     "tool_calls_by_name" => calls.group_by { |call| call["name"] }.transform_values(&:length).sort.to_h,
     "skill_evidence" => skill_evidence.uniq,
     "hook_deliveries" => hook_deliveries,
     "question_mark_messages" => questions.length,
     "question_texts" => include_question_text ? questions : "omitted",
     "timestamps" => timestamps.empty? ? "unknown" : {"first" => timestamps.first.iso8601(6), "last" => timestamps.last.iso8601(6), "span_seconds" => timestamps.last - timestamps.first},
     "observed_subagent_tool_calls" => subagent_count(calls),
     "cost" => "unknown (not measured by this parser)",
     "human_interventions" => "unknown (questions do not establish whether a human responded)",
     "malformed_lines" => malformed,
     "limitations" => ["Counts cover this transcript file only; continuation-chain aggregation and duplicate usage accounting are not performed.",
                       "Only tool events present in the transcript are counted; an observed subagent count of zero means no matching tool event appeared, not that no subagent work occurred.",
                       "Question-mark message count only records assistant messages containing '?'; it does not establish a clarification request or human intervention.",
                       "A SKILL.md path reference is not evidence that the file read succeeded; hook context markers indicate text presence only, not a successful skill read or invocation."]}
  rescue Errno::ENOENT
    {"source" => File.basename(path), "agent" => agent, "status" => "unknown", "reason" => "transcript missing"}
  end

  def tool_calls(event, agent)
    case agent
    when "claude"
      return [] unless event["type"] == "assistant"
      message = event["message"].is_a?(Hash) ? event["message"] : event
      Array(message["content"]).filter_map do |block|
        next unless block.is_a?(Hash) && block["type"] == "tool_use"
        {"name" => block["name"].to_s, "id" => block["id"]}
      end
    when "codex"
      item = event["item"]
      return [] unless event["type"] == "item.started" && item.is_a?(Hash)
      return [] unless %w[function_call tool_call command_execution mcp_tool_call web_search].include?(item["type"])
      [{"name" => (item["name"] || item["tool_name"] || item["type"] || "unknown").to_s, "id" => item["call_id"] || item["id"]}]
    end
  end

  def skill_observations(event, agent)
    evidence = []
    tool_calls(event, agent).each do |call|
      if call["name"].match?(/\Askill\z/i)
        skill = event.dig("message", "content")&.find { |block| block.is_a?(Hash) && block["type"] == "tool_use" && block["name"] == call["name"] }&.dig("input", "skill")
        evidence << {"kind" => "skill_tool_call", "tool" => call["name"], "skill" => skill}.compact
      end
      input = if agent == "claude"
                Array(event.dig("message", "content")).find { |block| block.is_a?(Hash) && block["type"] == "tool_use" && block["name"] == call["name"] }&.fetch("input", {})
              else
                item = event["item"] || {}
                item["arguments"] || item["command"]
              end
      text = input.is_a?(Hash) ? input.values.grep(String).join(" ") : input.to_s
      if call["name"].match?(/\A(?:Read|read_file|cat|exec_command|command_execution)\z/) && text.match?(%r{(?:^|[\s"'])[^\s"']*SKILL\.md\b}i)
        evidence << {"kind" => "skill_file_reference_in_tool_call", "tool" => call["name"]}
      end
    end
    evidence
  end

  def hook_delivery(event)
    subtype = event["subtype"] || event["type"]
    return unless subtype.to_s.match?(/\Ahook_response\z/i)

    output = event["output"]
    output = JSON.parse(output) if output.is_a?(String)
    output = {} unless output.is_a?(Hash)
    hook_output = output["hookSpecificOutput"].is_a?(Hash) ? output["hookSpecificOutput"] : {}
    context = hook_output["additionalContext"]
    context = "" unless context.is_a?(String)
    markers = %w[ruby-plainspoken rubypowers].select { |marker| context.downcase.include?(marker) }

    {"event" => hook_output["hookEventName"] || event["hook_event"] || "unknown",
     "name" => event["hook_name"] || event["name"] || "unknown",
     "exit_code" => event["exit_code"].is_a?(Numeric) ? event["exit_code"] : "unknown",
     "outcome" => event["outcome"] || "unknown",
     "additional_context_present" => !context.empty?,
     "plugin_markers_in_context" => markers}
  rescue JSON::ParserError
    {"event" => event["hook_event"] || "unknown",
     "name" => event["hook_name"] || event["name"] || "unknown",
     "exit_code" => event["exit_code"].is_a?(Numeric) ? event["exit_code"] : "unknown",
     "outcome" => event["outcome"] || "unknown",
     "additional_context_present" => false,
     "plugin_markers_in_context" => []}
  end

  def assistant_question_text(event, agent)
    text = assistant_text(event, agent)
    text if text&.include?("?")
  end

  def assistant_text(event, agent)
    case agent
    when "claude"
      return unless event["type"] == "assistant"
      message = event["message"].is_a?(Hash) ? event["message"] : event
      Array(message["content"]).filter_map { |block| block["text"] if block.is_a?(Hash) && block["type"] == "text" }.join("\n")
    when "codex"
      item = event["item"]
      return unless item.is_a?(Hash) && %w[agent_message assistant_message].include?(item["type"])
      item["text"].to_s
    end
  end

  def subagent_count(calls)
    calls.count { |call| call["name"].match?(/\A(?:Task|Agent|spawn_agent|delegate|subagent)\b/i) }
  end

  def parse_time(value)
    Time.parse(value) if value.is_a?(String)
  rescue ArgumentError
    nil
  end
end

if $PROGRAM_NAME == __FILE__
  unless ARGV.length == 2
    warn "usage: session_metrics.rb claude|codex TRANSCRIPT"
    exit 2
  end
  puts JSON.pretty_generate(SessionMetrics.parse(ARGV[1], agent: ARGV[0]))
end
