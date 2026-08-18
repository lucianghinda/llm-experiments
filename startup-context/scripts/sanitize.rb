#!/usr/bin/env ruby
# frozen_string_literal: true

# The gate between results-raw/ (gitignored) and results/ (committed).
#
#   ruby startup-context/scripts/sanitize.rb
#   ruby startup-context/scripts/sanitize.rb --check   # report, copy nothing
#
# This experiment's transcripts contain no source code, because the task was
# "Reply with exactly: OK". What they do contain is the machine: where its
# directories are, and a name-by-name list of every plugin, skill, subagent,
# slash command and MCP server installed on it.
#
# The counts are the finding. The names and the paths are a description of one
# person's laptop, and a reader needs neither to check a number in RESULTS.md:
# every claim there is a difference between two token totals. So the lists are
# replaced by their lengths and the paths by placeholders.
#
# Secrets are a hard failure rather than a redaction, because a secret in a
# transcript should stop a commit and be looked at, not be quietly rewritten
# into something that looks safe.

require "fileutils"
require "json"
require "tmpdir"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
RAW = File.join(EXPERIMENT_DIR, "results-raw")
OUT = File.join(EXPERIMENT_DIR, "results")
check_only = ARGV.include?("--check")

HOME = Dir.home
REPO_ROOT = File.expand_path("..", EXPERIMENT_DIR)

FORBIDDEN = {
  "AWS-style key" => /AKIA[0-9A-Z]{16}/,
  "private key block" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  "bearer token" => /\b(?:sk|pk)-[A-Za-z0-9_-]{20,}/,
  "OAuth access token" => /\bsk-ant-[A-Za-z0-9_-]{20,}/,
  "generic api secret" => /(?:api[_-]?key|secret|password|refresh_token)["'\s:=]+[A-Za-z0-9_\-]{24,}/i
}.freeze

# Claude Code names its per-project state directory after the working directory
# with every "/" and every "_" turned into "-". A host path therefore appears
# twice in a transcript, once as itself and once as
# "-Users-someone-Dropbox-...", and no path-shaped regex finds the second one.
# Every redaction below is applied to both spellings.
def slug(path)
  path.gsub(%r{[/_]}, "-")
end

# The neutral working directory is a fresh mktmpdir. On macOS that sits under a
# per-user token in /var/folders which is stable for the account, so the tail is
# random but the root identifies the machine as surely as the home path does.
def temp_roots
  root = File.expand_path(Dir.tmpdir)
  # Longest first: replacing "/var/folders/..." before "/private/var/folders/..."
  # leaves a stranded "/private" in front of the placeholder.
  [root, "/private#{root}", root.sub(%r{\A/private}, "")].uniq.sort_by { |r| -r.length }
end

# The project directory behind the host-project rows is passed to probe.rb
# through the environment and is deliberately not written down anywhere in the
# repository, so this script cannot be told what it is. It can be read back out
# of the raw runs, and it has to be: it is the one host path that lands in a
# transcript as ordinary content rather than in a field with a known name.
def discover_project_dirs(raw)
  dirs = []
  Dir.glob(File.join(raw, "**", "meta.json")).each do |path|
    meta = begin
      JSON.parse(File.read(path))
    rescue StandardError
      next
    end
    next unless meta["cwd_kind"] == "project"

    transcript = File.join(File.dirname(path), "transcript.jsonl")
    next unless File.exist?(transcript)

    File.readlines(transcript).each do |line|
      event = begin
        JSON.parse(line)
      rescue JSON::ParserError
        next
      end
      dirs << event["cwd"] if event.is_a?(Hash) && event["subtype"] == "init" && event["cwd"]
    end
  end
  dirs.compact.uniq.reject(&:empty?)
end

# probe.rb already writes "<home>" into the argv it records, so each real path
# also has to be matched in its half-redacted spelling. Four variants per path:
# as it is, home-redacted, slugged, and slugged with the home part redacted.
def variants(path)
  [path, path.sub(HOME, "<home>"), slug(path), slug(path).sub(slug(HOME), "<home>")].uniq
end

# Ordered most specific first: a project directory lives under the home path, so
# redacting the home path first would leave the rest of the project path behind.
REDACTIONS =
  discover_project_dirs(RAW).flat_map { |d| variants(d).map { |v| [v, "<project>"] } } +
  variants(REPO_ROOT).map { |v| [v, "<repo>"] } +
  temp_roots.flat_map { |r| variants(r).map { |v| [v, "<tmp>"] } } +
  variants(HOME).map { |v| [v, "<home>"] }

# Whatever the ordered list missed. Left as a net rather than the main mechanism,
# because a generic match cannot tell a project from a home directory and would
# label both the same.
RESIDUAL = {
  "residual host path" => %r{/(?:Users|home)/(?!agent\b)[A-Za-z0-9._-]+},
  "residual slug-encoded host path" => %r{-(?:Users|home)-(?!agent\b)[A-Za-z0-9._-]+},
  "residual temp path" => %r{[-/](?:private[-/])?var[-/]folders[-/]},
  # The hole that let the worktree path through once: probe.rb writes "<home>"
  # into the argv it records, so a path under the home directory arrives here
  # already half-redacted and matches none of the patterns above. Below the
  # home directory only the agents' own dotfile directories are expected;
  # those are named the same on every machine. Anything else is a place on
  # somebody's disk.
  "location below the home directory" =>
    %r{<home>/(?!\.(?:claude|codex|llmx|nodenv)\b)[A-Za-z0-9._-]+}
}.freeze

def redact(text)
  REDACTIONS.reduce(text) { |acc, (from, to)| acc.gsub(from, to) }
end

# Fields whose value is a list of what is installed. metrics.json already
# carries every one of these as a plain count, so nothing measurable is lost.
NAMED_INVENTORY = %w[tools skills slash_commands terminal_slash_commands agents plugins].freeze
INVENTORY_NAME_LISTS = %w[installed_plugins mcp_servers_in_claude_json mcp_servers_in_config].freeze

def strip_init(event)
  NAMED_INVENTORY.each do |key|
    next unless event.key?(key)

    event["#{key}_count"] = Array(event.delete(key)).size
  end

  # MCP servers keep their status breakdown, because "one failed and four needed
  # auth" is a result, and lose their names, because those are a list of
  # accounts and endpoints.
  if event.key?("mcp_servers")
    servers = Array(event.delete("mcp_servers"))
    by_status = Hash.new(0)
    servers.each { |srv| by_status[(srv.is_a?(Hash) ? srv["status"] : "unknown").to_s] += 1 }
    event["mcp_servers_count"] = servers.size
    event["mcp_servers_by_status"] = by_status
  end
  event
end

# A SessionStart hook's stdout is the body of whatever skill or output style
# fired it. Its size is the measurement; its text is configuration.
def strip_hook(event)
  %w[output stdout stderr].each do |key|
    next unless event.key?(key)

    event["#{key}_bytes"] = event.delete(key).to_s.bytesize
  end
  event
end

def strip_transcript(text)
  text.lines.map do |line|
    event = begin
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
    next line unless event.is_a?(Hash)

    strip_init(event) if event["subtype"] == "init"
    strip_hook(event) if event["subtype"] == "hook_response"
    event.to_json + "\n"
  end.join
end

def strip_inventory(text)
  data = JSON.parse(text)
  data.each_value do |section|
    next unless section.is_a?(Hash)

    INVENTORY_NAME_LISTS.each do |key|
      next unless section.key?(key)

      section["#{key}_count"] = Array(section.delete(key)).size
    end
  end
  JSON.pretty_generate(data) + "\n"
end

# The guard runs on what is about to be written rather than on what went in: a
# stripper that silently stopped matching would otherwise publish the very list
# it was written to remove.
LEAK_KEYS = (NAMED_INVENTORY + %w[mcp_servers] + INVENTORY_NAME_LISTS).freeze

def leaks_inventory?(text)
  LEAK_KEYS.any? { |key| text.include?(%("#{key}":[)) || text.include?(%("#{key}": [)) }
end

# The project label is the project's folder name, which is the same fact as the
# project path in one word, so it goes the same way.
def strip_labels(text)
  data = JSON.parse(text)
  rows = data.is_a?(Array) ? data : [data]
  rows.each { |row| row["project_label"] = "<project>" if row.is_a?(Hash) && row["project_label"] }
  JSON.pretty_generate(data) + "\n"
rescue JSON::ParserError
  text
end

COPIED = %w[metrics.json meta.json transcript.jsonl stderr.log agent-version.txt].freeze
LABELLED = %w[metrics.json meta.json summary.json].freeze

problems = []
copied = 0

Dir.glob(File.join(RAW, "**", "*")).sort.each do |path|
  next unless File.file?(path)

  rel = path.sub(RAW + "/", "")
  base = File.basename(path)
  next unless COPIED.include?(base) || %w[summary.json inventory.json].include?(base)

  text = redact(File.read(path))
  text = strip_transcript(text) if base == "transcript.jsonl"
  text = strip_inventory(text) if base == "inventory.json"
  text = strip_labels(text) if LABELLED.include?(base)

  problems << "#{rel}: publishes a list of installed items" if leaks_inventory?(text)
  FORBIDDEN.each { |label, pattern| problems << "#{rel}: #{label}" if text.match?(pattern) }
  RESIDUAL.each { |label, pattern| problems << "#{rel}: #{label}" if text.match?(pattern) }

  next if check_only

  dest = File.join(OUT, rel)
  FileUtils.mkdir_p(File.dirname(dest))
  File.write(dest, text)
  copied += 1
end

unless problems.empty?
  warn "REFUSING to publish. #{problems.size} problem(s):"
  problems.first(40).each { |problem| warn "  #{problem}" }
  # Remove whatever was written before the problem was found, so a failed run
  # never leaves a half-sanitized tree that looks finished.
  FileUtils.rm_rf(OUT) unless check_only
  exit 1
end

puts check_only ? "clean: nothing copied" : "copied #{copied} file(s) into results/"
