#!/usr/bin/env ruby
# frozen_string_literal: true

# Writes each project's .claude/settings.json from its .example file.
#
# A statusLine command has to be an absolute path, and this repo does not
# commit absolute paths, so the real settings file is generated here and
# kept out of git.

ROOT = __dir__

Dir.glob(File.join(ROOT, '*', '.claude', 'settings.json.example')).sort.each do |example|
  target = example.delete_suffix('.example')
  File.write(target, File.read(example).gsub('<experiment-root>', ROOT))
  puts "wrote #{target.delete_prefix("#{ROOT}/")}"
end
