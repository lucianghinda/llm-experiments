#!/usr/bin/env ruby
# frozen_string_literal: true

# Experiment harness. Captures the real status line payload and the
# environment the command runs in, then delegates to the project's own
# status line so the session still shows a normal bar.
#
# Usage, from a project's .claude/settings.json:
#   "command": "<experiment-root>/probe.rb <project-folder>"

require 'json'
require 'fileutils'

ROOT    = __dir__
project = ARGV[0] || 'unknown'
raw     = $stdin.read

payload = begin
  JSON.parse(raw)
rescue StandardError => e
  { 'unparseable' => raw, 'error' => e.message }
end

snapshot = {
  'project' => project,
  'captured_by' => 'probe.rb',
  # Settles whether a relative command path could resolve.
  'probe_cwd' => Dir.pwd,
  # Settles whether $CLAUDE_PROJECT_DIR is available to statusLine.
  'env' => {
    'CLAUDE_PROJECT_DIR' => ENV.fetch('CLAUDE_PROJECT_DIR', nil),
    'PWD' => ENV.fetch('PWD', nil),
    'COLUMNS' => ENV.fetch('COLUMNS', nil),
    'LINES' => ENV.fetch('LINES', nil)
  },
  'payload' => payload
}

results = File.join(ROOT, 'results-raw')
FileUtils.mkdir_p(results)
File.write(File.join(results, "#{project}.json"), "#{JSON.pretty_generate(snapshot)}\n")

# Draw the real bar so the session looks normal.
script = File.join(ROOT, project, '.claude', 'statusline.rb')
if File.executable?(script)
  IO.popen([script], 'r+') do |io|
    io.write(raw)
    io.close_write
    print io.read
  end
else
  puts "probe: #{project}"
end
