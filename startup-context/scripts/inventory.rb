#!/usr/bin/env ruby
# frozen_string_literal: true

# Records what is installed on this machine for each agent, read off disk.
#
#   ruby startup-context/scripts/inventory.rb
#
# The probe transcripts tell you how much context arrived. They do not tell you
# where it came from, and for Codex they say almost nothing at all: Codex has no
# equivalent of Claude's init event, so the only way to see its loaded surface
# is to look at the files it reads.
#
# Sizes are bytes, and bytes are converted to a rough token estimate at 4 bytes
# per token. That ratio is a rule of thumb, not a measurement, and it is here to
# put a file's weight on the same scale as the transcript numbers, not to be
# quoted as a token count.
#
# No absolute path is written out. Only counts, sizes and names.

require "json"

HOME = Dir.home
BYTES_PER_TOKEN = 4

def count_entries(dir, pattern = "*")
  return 0 unless Dir.exist?(dir)

  Dir.glob(File.join(dir, pattern)).size
end

def file_stat(path)
  return nil unless File.file?(path)

  bytes = File.size(path)
  { "bytes" => bytes, "lines" => File.readlines(path).size,
    "approx_tokens" => (bytes / BYTES_PER_TOKEN.to_f).round }
end

def json_or_nil(path)
  JSON.parse(File.read(path))
rescue StandardError
  nil
end

claude_dir = File.join(HOME, ".claude")
settings = json_or_nil(File.join(claude_dir, "settings.json")) || {}
# The MCP servers a user configures by hand live in ~/.claude.json, at the top
# of the home directory, not in ~/.claude/. Reading only the second one reports
# zero servers on a machine that clearly has some.
claude_json = json_or_nil(File.join(HOME, ".claude.json")) || {}
installed = json_or_nil(File.join(claude_dir, "plugins", "installed_plugins.json")) || {}

hooks = settings["hooks"] || {}
hook_count = hooks.values.flatten.sum { |g| g.is_a?(Hash) ? Array(g["hooks"]).size : 0 }

claude = {
  "global_memory_file" => file_stat(File.join(claude_dir, "CLAUDE.md")),
  "skills_dir_entries" => count_entries(File.join(claude_dir, "skills")),
  "commands_dir_entries" => count_entries(File.join(claude_dir, "commands"), "**/*.md"),
  "agents_dir_entries" => count_entries(File.join(claude_dir, "agents"), "**/*.md"),
  "plugin_repos" => count_entries(File.join(claude_dir, "plugins", "repos")),
  "installed_plugins" => (installed["plugins"] || {}).keys.sort,
"claude_json_bytes" => file_stat(File.join(HOME, ".claude.json"))&.dig("bytes"),
"claude_json_project_entries" => (claude_json["projects"] || {}).size,
  "settings_hook_events" => hooks.keys.sort,
  "settings_hook_count" => hook_count,
  "mcp_servers_in_claude_json" => (claude_json["mcpServers"] || {}).keys.sort,
  "settings_bytes" => file_stat(File.join(claude_dir, "settings.json"))&.dig("bytes")
}

codex_dir = File.join(HOME, ".codex")
config_path = File.join(codex_dir, "config.toml")
config_text = File.exist?(config_path) ? File.read(config_path) : ""

codex = {
  "global_memory_file" => file_stat(File.join(codex_dir, "AGENTS.md")),
  "config_file" => file_stat(config_path),
  "mcp_servers_in_config" => config_text.scan(/^\[mcp_servers\.([\w-]+)\]/).flatten.sort,
  "project_entries_in_config" => config_text.scan(/^\[projects\./).size,
  "agents_dir_entries" => count_entries(File.join(codex_dir, "agents")),
  "skills_dir_entries" => count_entries(File.join(codex_dir, "skills")),
  "prompts_dir_entries" => count_entries(File.join(codex_dir, "prompts")),
  "plugins_dir_entries" => count_entries(File.join(codex_dir, "plugins")),
  "rules_dir_entries" => count_entries(File.join(codex_dir, "rules")),
  "hooks_file" => file_stat(File.join(codex_dir, "hooks.json"))
}

# opencode follows the XDG layout: configuration, skills, agents and commands in
# ~/.config/opencode, and credentials, sessions and a database in
# ~/.local/share/opencode. Only the config side is counted here. The data side
# holds live tokens and is never read by this script.
#
# opencode.json is not sized like the other two memory files, because it is not
# a memory file: it is settings, and at least one of them on this machine is a
# bearer token. The count of MCP servers is taken from it; the file is not.
opencode_config = File.join(HOME, ".config", "opencode")
opencode_json = File.join(opencode_config, "opencode.json")
opencode_settings = json_or_nil(opencode_json) || {}

opencode = {
  "config_file_bytes" => File.file?(opencode_json) ? File.size(opencode_json) : nil,
  "global_rules_file" => file_stat(File.join(opencode_config, "global-rules.md")),
  "mcp_server_count" => (opencode_settings["mcp"] || {}).size,
  "command_count" => (opencode_settings["command"] || {}).size,
  "skills_dir_entries" => count_entries(File.join(opencode_config, "skills")),
  "agents_dir_entries" => count_entries(File.join(opencode_config, "agents")),
  "commands_dir_entries" => count_entries(File.join(opencode_config, "commands"), "**/*"),
  "plugins_dir_entries" => count_entries(File.join(opencode_config, "plugins")),
  "node_modules_entries" => count_entries(File.join(opencode_config, "node_modules"))
}

report = { "claude" => claude, "codex" => codex, "opencode" => opencode,
           "bytes_per_token_assumed" => BYTES_PER_TOKEN }


out = File.join(File.expand_path("..", __dir__), "results-raw", "inventory.json")
Dir.mkdir(File.dirname(out)) unless Dir.exist?(File.dirname(out))
File.write(out, JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
