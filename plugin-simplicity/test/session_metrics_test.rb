# frozen_string_literal: true

require "tmpdir"
require "json"
require_relative "../scripts/session_metrics"

class SessionMetricsTest
  def with_transcript(lines)
    Dir.mktmpdir("session-metrics") do |root|
      path = File.join(root, "transcript.txt")
      File.write(path, lines.map { |line| JSON.generate(line) + "\n" }.join)
      yield path
    end
  end

  def test_claude_tools_skill_read_and_explicit_questions
    events = [
      {"type" => "assistant", "timestamp" => "2026-10-20T10:00:00Z", "message" => {"content" => [
        {"type" => "text", "text" => "Should I proceed?"},
        {"type" => "tool_use", "id" => "call-1", "name" => "Read", "input" => {"file_path" => "/skills/example/SKILL.md"}}
      ]}},
      {"type" => "assistant", "timestamp" => "2026-10-20T10:01:00Z", "message" => {"content" => [
        {"type" => "tool_use", "id" => "call-2", "name" => "Read", "input" => {"file_path" => "/app/lib/a.rb"}},
        {"type" => "text", "text" => "Done."}
      ]}}
    ]
    with_transcript(events) do |path|
      result = SessionMetrics.parse(path, agent: "claude")
      equal(2, result["tool_call_count"])
      equal({"Read" => 2}, result["tool_calls_by_name"])
      equal([{"kind" => "skill_file_reference_in_tool_call", "tool" => "Read"}], result["skill_evidence"])
      equal("omitted", result["question_texts"])
      equal(1, result["question_mark_messages"])
      equal(60.0, result.dig("timestamps", "span_seconds"))
      match(/unknown/, result["human_interventions"])
      equal(0, result["observed_subagent_tool_calls"])
      refute(result.to_json.include?("Done."))
      equal(["Should I proceed?"], SessionMetrics.parse(path, agent: "claude", include_question_text: true)["question_texts"])
    end
  end

  def test_codex_tool_events_count_started_items_once_and_questions_are_assistant_only
    events = [
      {"type" => "item.started", "item" => {"id" => "i1", "type" => "command_execution", "command" => "rg foo"}},
      {"type" => "item.started", "item" => {"id" => "i1", "type" => "command_execution", "command" => "rg foo"}},
      {"type" => "item.started", "item" => {"id" => "i2", "type" => "function_call", "name" => "Task", "call_id" => "sub-1"}},
      {"type" => "item.completed", "item" => {"id" => "m1", "type" => "agent_message", "text" => "Can you confirm?"}},
      {"type" => "item.completed", "item" => {"id" => "m2", "type" => "user_message", "text" => "No question?"}}
    ]
    with_transcript(events) do |path|
      result = SessionMetrics.parse(path, agent: "codex")
      equal(2, result["tool_call_count"])
      equal({"Task" => 1, "command_execution" => 1}, result["tool_calls_by_name"])
      equal(1, result["question_mark_messages"])
      equal("omitted", result["question_texts"])
      equal(1, result["observed_subagent_tool_calls"])
      equal("unknown", result["timestamps"])
    end
  end

  def test_missing_transcript_and_malformed_lines_are_explicit
    missing = SessionMetrics.parse("/missing/transcript", agent: "claude")
    equal("unknown", missing["status"])
    with_transcript([]) do |path|
      File.write(path, "not json\n")
      result = SessionMetrics.parse(path, agent: "claude")
      equal(1, result["malformed_lines"])
      equal(0, result["tool_call_count"])
      match(/unknown/, result["cost"])
    end
  end

  def test_hook_response_reports_sanitized_delivery_metadata
    events = [
      {"type" => "system", "subtype" => "hook_response", "hook_name" => "SessionStart:startup", "hook_event" => "SessionStart", "exit_code" => 0, "outcome" => "success",
       "output" => JSON.generate("hookSpecificOutput" => {"hookEventName" => "SessionStart", "additionalContext" => "using-rubypowers: full private hook text"})},
      {"type" => "system", "subtype" => "hook_response", "output" => "not json"}
    ]
    with_transcript(events) do |path|
      result = SessionMetrics.parse(path, agent: "claude")
      equal([{"event" => "SessionStart", "name" => "SessionStart:startup", "exit_code" => 0, "outcome" => "success", "additional_context_present" => true, "plugin_markers_in_context" => ["rubypowers"]},
             {"event" => "unknown", "name" => "unknown", "exit_code" => "unknown", "outcome" => "unknown", "additional_context_present" => false, "plugin_markers_in_context" => []}], result["hook_deliveries"])
      refute(result.to_json.include?("full private hook text"))
    end
  end
end

def equal(expected, actual)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end

def match(pattern, actual)
  raise "expected #{actual.inspect} to match #{pattern.inspect}" unless pattern.match?(actual)
end

def refute(value)
  raise "expected false" if value
end

tests = SessionMetricsTest.new
tests.methods.grep(/^test_/).sort.each do |name|
  tests.public_send(name)
  puts "PASS #{name}"
end
