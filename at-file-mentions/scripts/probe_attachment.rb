#!/usr/bin/env ruby
# frozen_string_literal: true

# Does `@path` put the file in context? Answered behaviourally, not by counting
# tokens.
#
#   ruby at-file-mentions/scripts/probe_attachment.rb --app campfire --agent claude
#   ruby at-file-mentions/scripts/probe_attachment.rb --app campfire --agent codex
#
# Why not token counts: probe_mention.rb reads context from the usage figures,
# which works for Claude and does not work for Codex. Codex reports once per
# turn and its totals move by ~800 tokens between identical runs - the same size
# as attaching a small file - so the measurement cannot distinguish the effect
# from its own noise. Two runs of the same probe disagreed on four of seven
# cases.
#
# This asks a question that can only be answered from the file's contents, and
# forbids running anything. If the file was attached the agent answers from what
# it already has. If it was not, it has to refuse, guess, or reach for a tool -
# and the tool call is visible in the transcript whatever the token accounting
# says.
#
# The needle is a private method name that appears nowhere but in that file, so
# a correct answer cannot come from the model's memory of the repository or from
# the path alone.

require "base64"
require "json"
require_relative "../../containers/scripts/lib/kit"

app_key = "campfire"
agent = "claude"
needle = nil

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--app" then app_key = args.shift
  when "--agent" then agent = args.shift
  when "--needle" then needle = args.shift
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end
abort "--agent must be claude or codex" unless %w[claude codex].include?(agent)

EXPERIMENT_DIR = File.expand_path("..", __dir__)
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]
bug = bugs.find { |b| b["app"] == app_key } or abort "no bug for app #{app_key}"
impl = bug["impl_files"].first

# Distinctive private method names, one per app. The needle has to be something
# the agent cannot produce without having read the file, so it must not be
# derivable from the path it was given.
#
# postcraftstudio was `api_auth`, which is the module name *and* the basename of
# app/controllers/concerns/api_auth.rb. An agent that could not see the file at
# all could answer it straight off the path, so the one check that is supposed
# to be decisive could report ATTACHED for a file that was never attached. It is
# now `verified_token`, a private method in that file. (It also appears in
# api_token.rb, which does not matter: what matters is that it cannot be guessed
# from the path, not that it is globally unique.)
NEEDLES = {
  "campfire" => "embedded_ipv4",
  "postcraftstudio" => "verified_token",
  "bookmarks" => "with_session_recovery"
}.freeze
needle ||= NEEDLES[app_key] or abort "no needle known for #{app_key}; pass --needle"

image = "llmx-app-#{app_key}:latest"
Kit.ensure_system_started!
abort "image #{image} not found" unless Kit.image_exists?(image)

QUESTION = "List the names of every method defined in that file, comma separated. " \
           "Do not run any command and do not read any file. If you cannot see the " \
           "file's contents, reply exactly: CANNOT SEE FILE."

CASES = {
  "@path" => "@#{impl}\n\n#{QUESTION}",
  "@path:line" => "@#{impl}:22\n\n#{QUESTION}",
  "path (control)" => "#{impl}\n\n#{QUESTION}"
}.freeze

READERS = {
  "claude" => <<~'RUBY',
    require "json"
    rs = STDIN.each_line.filter_map { |l| JSON.parse(l) rescue nil }
    text = rs.select { |r| r["type"] == "assistant" }.flat_map { |r|
      Array(r.dig("message", "content")).select { |c| c["type"] == "text" }.map { |c| c["text"] }
    }.join(" ")
    tools = rs.select { |r| r["type"] == "assistant" }.sum { |r|
      Array(r.dig("message", "content")).count { |c| c["type"] == "tool_use" }
    }
    puts "TOOLS #{tools}"
    puts "ANSWER #{text.gsub(/\s+/, ' ')[0, 400]}"
  RUBY
  "codex" => <<~'RUBY'
    require "json"
    rs = STDIN.each_line.filter_map { |l| JSON.parse(l) rescue nil }
    text = rs.select { |r| r["type"] == "item.completed" && r.dig("item", "type") == "agent_message" }
             .map { |r| r.dig("item", "text").to_s }.join(" ")
    tools = rs.count { |r| r["type"] == "item.completed" && r.dig("item", "type") == "command_execution" }
    puts "TOOLS #{tools}"
    puts "ANSWER #{text.gsub(/\s+/, ' ')[0, 400]}"
  RUBY
}.freeze

def b64(text) = Base64.strict_encode64(text)

invoke =
  if agent == "claude"
    'claude -p "$P" --output-format stream-json --verbose --permission-mode bypassPermissions ' \
      "--model #{ENV.fetch('LLMX_CLAUDE_MODEL', 'claude-opus-5')}"
  else
    %(printf '%s' "$P" | codex exec --json --dangerously-bypass-approvals-and-sandbox ) +
      "--skip-git-repo-check --ignore-user-config --ephemeral -C /workspace/app -"
  end

script = +<<~SH
  set -e
  cd /workspace/app
  git checkout -q trial/#{bug['id']}
  echo "#{b64(READERS.fetch(agent))}" | base64 -d > /tmp/read.rb
SH

CASES.each_key.with_index do |label, i|
  script << <<~SH
    P=$(echo "#{b64(CASES[label])}" | base64 -d)
    echo "===CASE #{i}==="
    #{invoke} 2>/dev/null | ruby /tmp/read.rb
  SH
end

Kit.log "asking #{agent} to name the methods in #{impl} without reading it"
Kit.log "needle: #{needle} (appears only in that file)"
out, = Kit.try("container", "run", "--rm", *Kit.run_args, image, "bash", "-lc", script)

blocks = out.split(/^===CASE \d+===$/).drop(1)
puts
CASES.each_key.with_index do |label, i|
  body = blocks[i].to_s
  tools = body[/^TOOLS (\d+)/, 1]
  answer = body[/^ANSWER (.*)$/, 1].to_s
  saw = answer.include?(needle)
  refused = answer.include?("CANNOT SEE FILE")

  verdict =
    if saw && tools.to_i.zero? then "ATTACHED - named #{needle} with no tool call"
    elsif refused && tools.to_i.zero? then "not attached - said it cannot see the file"
    elsif tools.to_i.positive? then "not attached - had to run #{tools} tool call(s)"
    else "unclear"
    end

  puts format("  %-16s tools=%-3s needle=%-5s  %s", label, tools || "?", saw, verdict)
  puts format("  %-16s %s", "", answer[0, 150]) unless answer.empty?
  puts
end
