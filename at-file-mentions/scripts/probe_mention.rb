#!/usr/bin/env ruby
# frozen_string_literal: true

# Does `@path` actually attach the file, and does a `:line` suffix stop it?
#
#   ruby at-file-mentions/scripts/probe_mention.rb --app campfire
#
# This is the positive control the experiment was missing. Every other check in
# this harness verifies that a trial ran correctly; none verified that the
# manipulation under test had any effect at all. It did not: the prompts append
# a line number to every hinted path, `@file.rb:22` does not resolve to a file,
# and so both the bare and at conditions sent inert text. The trials ran green
# and the conclusion was confidently wrong.
#
# Run this before trusting any comparison between conditions. If `@path` and
# `path` do not differ by roughly the file's token count, the mention is not
# doing anything and the experiment is measuring nothing.

require "json"
require "base64"
require_relative "../../containers/scripts/lib/kit"

app_key = "campfire"
agent = "claude"
model = nil

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--app" then app_key = args.shift
  when "--agent" then agent = args.shift
  when "--model" then model = args.shift
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

EXPERIMENT_DIR = File.expand_path("..", __dir__)
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]
bug = bugs.find { |b| b["app"] == app_key } or abort "no bug for app #{app_key}"

image = "llmx-app-#{app_key}:latest"
Kit.ensure_system_started!
abort "image #{image} not found" unless Kit.image_exists?(image)

impl = bug["impl_files"].first
test = bug["test_file"]

# Ask for a one-word answer so the run is short and no tool call can fetch the
# file. Whatever context the first request carries came from the prompt alone.
tail = "Reply with the word OK and nothing else."

CASES = [
  ["no file mentioned", tail],
  ["path", "#{impl} #{tail}"],
  ["@path", "@#{impl} #{tail}"],
  ["path:line", "#{impl}:22 #{tail}"],
  ["@path:line", "@#{impl}:22 #{tail}"],
  ["@test @impl", "@#{test} @#{impl} #{tail}"],
  ["@test:line @impl:line", "@#{test}:82 @#{impl}:22 #{tail}"]
].freeze

abort "--agent must be claude or codex" unless %w[claude codex].include?(agent)
model ||= agent == "claude" ? ENV.fetch("LLMX_CLAUDE_MODEL", "claude-opus-5") : ENV.fetch("LLMX_CODEX_MODEL", nil)

# Claude reports usage per model request, so the first assistant event is the
# first request. Codex reports once per turn - normally useless for this, because
# a turn swallows every tool call it made. Here it is exactly right: the prompt
# asks for a single word, so the turn contains no tool calls and its input total
# is prompt-carried context and nothing else. That is why this probe can answer
# for Codex when the trials cannot.
# Quoted heredocs: these are programs for the container's ruby, not templates.
# An unquoted one interpolates #{...} here instead of there.
READERS = {
  "claude" => <<~'RUBY',
    require "json"
    e = STDIN.each_line.filter_map { |l| JSON.parse(l) rescue nil }
             .find { |x| x["type"] == "assistant" }
    u = (e && e.dig("message", "usage")) || {}
    puts u["input_tokens"].to_i + u["cache_creation_input_tokens"].to_i + u["cache_read_input_tokens"].to_i
  RUBY
  "codex" => <<~'RUBY'
    require "json"
    rs = STDIN.each_line.filter_map { |l| JSON.parse(l) rescue nil }
    t = rs.find { |x| x["type"] == "turn.completed" }
    u = (t && t["usage"]) || {}
    tools = rs.count { |x| x["type"] == "item.completed" && x.dig("item", "type") == "command_execution" }
    # input_tokens is cumulative for the turn and already includes cached ones.
    warn "WARNING: turn ran #{tools} tool call(s); the total is not prompt-only" if tools.positive?
    puts u["input_tokens"].to_i
  RUBY
}.freeze

READER = READERS.fetch(agent)

# Everything crosses the shell boundary base64-encoded, the same way run_trial.rb
# passes its prompt. A prompt here contains @, quotes and paths, and the reader
# contains newlines and braces; interpolating either into a shell command is how
# the first version of this script silently produced no output at all.
def b64(text) = Base64.strict_encode64(text)

script = +<<~SH
  set -e
  cd /workspace/app
  git checkout -q trial/#{bug['id']}
  echo "#{b64(READER)}" | base64 -d > /tmp/first_ctx.rb
  echo "BYTES #{impl} $(wc -c < #{impl})"
  echo "BYTES #{test} $(wc -c < #{test})"
SH

invoke =
  if agent == "claude"
    %(claude -p "$P" --output-format stream-json --verbose --permission-mode bypassPermissions) +
      (model ? " --model #{model}" : "")
  else
    # Same flags a trial uses, prompt on stdin. --ephemeral and
    # --ignore-user-config keep it as close to a clean trial as the probe needs.
    %(printf '%s' "$P" | codex exec --json --dangerously-bypass-approvals-and-sandbox ) +
      %(--skip-git-repo-check --ignore-user-config --ephemeral -C /workspace/app) +
      (model ? " --model #{model}" : "") + " -"
  end

CASES.each_with_index do |(_label, prompt), i|
  script << <<~SH
    P=$(echo "#{b64(prompt)}" | base64 -d)
    printf 'CASE %s\\t' #{i}
    #{invoke} 2>/dev/null | ruby /tmp/first_ctx.rb
  SH
end

Kit.log "probing #{CASES.size} prompt forms against #{image} with #{agent}"
out, = Kit.try("container", "run", "--rm", *Kit.run_args, image, "bash", "-lc", script)

out.scan(/^BYTES (\S+) (\d+)/) { |f, n| puts format("  %-60s %s bytes", f, n) }

values = out.scan(/^CASE (\d+)\t(\d+)/).to_h { |i, v| [i.to_i, v.to_i] }
baseline = values[0]

puts
puts format("  %-24s %-10s %s", "prompt form", "first req", "vs no mention")
CASES.each_with_index do |(label, _), i|
  v = values[i] or next
  puts format("  %-24s %-10d %+d", label, v, v - baseline.to_i)
end

attached = values[2].to_i - values[1].to_i
inert = values[4].to_i - values[3].to_i
puts
puts format("  @path adds %+d tokens over a plain path", attached)
puts format("  @path:line adds %+d tokens over a plain path:line", inert)
puts
puts(attached > 200 ? "  the mention resolves: @path attaches the file" :
                      "  WARNING: @path attached nothing; the manipulation is inert")
puts(inert > 200 ? "  a line suffix does not stop it" :
                   "  a line suffix stops it: @path:line is literal text")
