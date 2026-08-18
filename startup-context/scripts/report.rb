#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the tables that go into RESULTS.md from summary.json and inventory.json.
#
#   ruby startup-context/scripts/report.rb            # print
#   ruby startup-context/scripts/report.rb --write    # also write results/tables.md
#
# Written rather than typed, so every number in the write-up can be regenerated
# and none of them is a transcription. The median is reported rather than the
# mean because there are three runs per condition and one slow or oddly cached
# run should not move the row.

require "json"
require_relative "conditions"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
rows = JSON.parse(File.read(File.join(EXPERIMENT_DIR, "results-raw", "summary.json")))
inventory = JSON.parse(File.read(File.join(EXPERIMENT_DIR, "results-raw", "inventory.json")))

def median(values)
  sorted = values.compact.sort
  return nil if sorted.empty?

  mid = sorted.size / 2
  sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
end

# The sign has to be carried separately. Reversing "-1898" and scanning it for
# runs of digits drops the minus, which turns "removing this made the prompt
# 1,898 tokens BIGGER" into the opposite claim.
def commas(n)
  return "-" if n.nil?

  value = n.to_i
  grouped = value.abs.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
  value.negative? ? "-#{grouped}" : grouped
end

groups = rows.group_by { |r| [r["agent"], r["condition"]] }
ORDER = {
  "claude" => %w[host-project host-full host-default-model host-no-mcp host-no-skills host-no-subagents host-lean host-leanest host-safe-mode container],
  "codex" => %w[host-project host-full host-no-mcp host-no-config container],
  "opencode" => %w[host-project host-full host-no-mcp host-pure host-no-config host-leanest container]
}.freeze

stats = {}
groups.each do |(agent, condition), runs|
  stats[[agent, condition]] = {
    runs: runs.size,
    tokens: median(runs.map { |r| r["startup_context_tokens"] }),
    min: runs.map { |r| r["startup_context_tokens"] }.compact.min,
    max: runs.map { |r| r["startup_context_tokens"] }.compact.max,
    cost: median(runs.map { |r| r["cost_usd"] }.compact.map { |c| (c * 10_000).round })&.fdiv(10_000),
    wall: median(runs.map { |r| r["wall_seconds"] }.compact.map { |w| (w * 10).round })&.fdiv(10),
    sample: runs.first,
    # The label comes from conditions.rb, not from the note recorded in
    # meta.json at run time, so a description corrected after the fact is
    # corrected in the report too.
    note: CONDITIONS.find { |c| c[:agent] == agent && c[:key] == condition }&.dig(:note) || runs.first["note"],
    clean: runs.all? { |r| r["clean_probe"] }
  }
end

out = +""

out << "### Startup context: what arrives before the first token of work\n\n"
out << "| Agent | Condition | Runs | Startup tokens (median) | Spread | Times the container floor | What it is |\n"
out << "|---|---|---:|---:|---:|---:|---|\n"
ORDER.each do |agent, conditions|
  floor = stats.dig([agent, "container"], :tokens)
  conditions.each do |condition|
    s = stats[[agent, condition]] or next
    ratio = floor && floor.positive? ? format("%.2fx", s[:tokens].to_f / floor) : "-"
    spread = s[:min] == s[:max] ? "0" : "#{commas(s[:min])}-#{commas(s[:max])}"
    out << "| #{agent} | `#{condition}` | #{s[:runs]} | #{commas(s[:tokens])} | #{spread} | #{ratio} | #{s[:note]} |\n"
  end
end

out << "\n### What Claude reports loading, per condition\n\n"
out << "Claude emits an `init` event naming everything it attached. These are counts from that event, one representative run per condition.\n\n"
out << "| Condition | Tools | MCP servers | Skills | Slash commands | Subagents | Plugins | Hooks fired |\n"
out << "|---|---:|---:|---:|---:|---:|---:|---:|---:|\n"
ORDER["claude"].each do |condition|
  s = stats[["claude", condition]] or next
  r = s[:sample]
  out << "| `#{condition}` | #{r['tools_available']} | #{r['mcp_servers']} | #{r['skills']} | " \
         "#{r['slash_commands']} | #{r['subagents']} | #{r['plugins']} | #{r['hooks_fired']} | " \
         "#{commas(r['hook_injected_bytes'])} |\n"
end

out << "\n### What each layer costs\n\n"
out << "Each row is the difference between two conditions that are identical apart from one layer.\n\n"
out << "| Agent | Layer | Measured as | Tokens |\n|---|---|---|---:|\n"

def delta(stats, agent, from, to)
  a = stats.dig([agent, from], :tokens)
  b = stats.dig([agent, to], :tokens)
  return nil unless a && b

  a - b
end

[["claude", "MCP servers", "host-full", "host-no-mcp"],
 ["claude", "Skills and slash commands", "host-full", "host-no-skills"],
 ["claude", "Subagent catalogue and the Task tool", "host-full", "host-no-subagents"],
 ["claude", "MCP, skills and subagents together", "host-full", "host-leanest"],
 ["claude", "MCP + skills together", "host-full", "host-lean"],
 ["claude", "Everything the user added", "host-full", "host-safe-mode"],
 ["claude", "Being inside a real project", "host-project", "host-full"],
 ["codex", "MCP servers", "host-full", "host-no-mcp"],
 ["codex", "config.toml and AGENTS.md", "host-full", "host-no-config"],
 ["codex", "Being inside a real project", "host-project", "host-full"],
 ["opencode", "MCP servers", "host-full", "host-no-mcp"],
 ["opencode", "External plugins", "host-full", "host-pure"],
 ["opencode", "The ~/.config/opencode directory", "host-full", "host-no-config"],
 ["opencode", "Config directory and plugins together", "host-full", "host-leanest"],
 ["opencode", "Being inside a real project", "host-project", "host-full"]].each do |agent, label, from, to|
  d = delta(stats, agent, from, to)
  next unless d

  out << "| #{agent} | #{label} | `#{from}` minus `#{to}` | #{commas(d)} |\n"
end

out << "\n### Cost and wall time of saying \"OK\"\n\n"
out << "Cost moves with the prompt cache, so it is reported and not compared. Token counts do not move.\n\n"
out << "| Agent | Condition | Median cost (USD) | Median wall (s) |\n|---|---|---:|---:|\n"
ORDER.each do |agent, conditions|
  conditions.each do |condition|
    s = stats[[agent, condition]] or next
    out << "| #{agent} | `#{condition}` | #{s[:cost] ? format('%.4f', s[:cost]) : 'not reported'} | #{s[:wall]} |\n"
  end
end

out << "\n### Installed surface on the host, read off disk\n\n"
out << "| Agent | Item | Value |\n|---|---|---:|\n"
c = inventory["claude"]
out << "| claude | global memory file (`CLAUDE.md`) | #{commas(c.dig('global_memory_file', 'bytes'))} bytes |\n"
out << "| claude | skill directories | #{c['skills_dir_entries']} |\n"
out << "| claude | installed plugins | #{Array(c['installed_plugins']).size} |\n"
out << "| claude | MCP servers configured by hand | #{Array(c['mcp_servers_in_claude_json']).size} |\n"
out << "| claude | session hooks configured | #{c['settings_hook_count']} |\n"
out << "| claude | `~/.claude.json` | #{commas(c['claude_json_bytes'])} bytes, #{c['claude_json_project_entries']} project entries |\n"
x = inventory["codex"]
out << "| codex | global memory file (`AGENTS.md`) | #{commas(x.dig('global_memory_file', 'bytes'))} bytes (~#{commas(x.dig('global_memory_file', 'approx_tokens'))} tokens) |\n"
out << "| codex | `config.toml` | #{commas(x.dig('config_file', 'bytes'))} bytes, #{x['project_entries_in_config']} project entries |\n"
out << "| codex | MCP servers in config | #{Array(x['mcp_servers_in_config']).size} |\n"
out << "| codex | skill directories | #{x['skills_dir_entries']} |\n"
out << "| codex | agent definitions | #{x['agents_dir_entries']} |\n"
out << "| codex | saved prompts | #{x['prompts_dir_entries']} |\n"
o = inventory["opencode"] || {}
out << "| opencode | `opencode.json` | #{commas(o['config_file_bytes'])} bytes |\n"
out << "| opencode | skill directories | #{o['skills_dir_entries']} |\n"
out << "| opencode | agent definitions | #{o['agents_dir_entries']} |\n"
out << "| opencode | MCP servers in config | #{o['mcp_server_count']} |\n"
out << "| opencode | plugin entries | #{o['plugins_dir_entries']} |\n"

notices = rows.flat_map { |r| Array(r["cli_notices"]) }.uniq
unless notices.empty?
  out << "\n### What the CLIs said about their own load\n\n"
  notices.each { |n| out << "- #{n}\n" }
end

dirty = rows.reject { |r| r["clean_probe"] }
unless dirty.empty?
  out << "\n### Runs that did not measure startup alone\n\n"
  dirty.each { |r| out << "- `#{r['run_dir']}` tool calls: #{r['tool_calls'].inspect}\n" }
end

puts out
if ARGV.include?("--write")
  dest = File.join(EXPERIMENT_DIR, "results")
  Dir.mkdir(dest) unless Dir.exist?(dest)
  File.write(File.join(dest, "tables.md"), out)
  warn "wrote results/tables.md"
end
