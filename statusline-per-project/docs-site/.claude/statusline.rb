#!/usr/bin/env ruby
# frozen_string_literal: true

# Status line for the docs-site project.
# Two lines: identity on top, a context window meter underneath.

require 'json'

RESET   = "\e[0m"
DIM     = "\e[2m"
MAGENTA = "\e[35m"
GREEN   = "\e[32m"
YELLOW  = "\e[33m"
RED     = "\e[31m"

FILLED = '█'
EMPTY  = '░'
WIDTH  = 16

def color_for(percent)
  return RED if percent >= 80
  return YELLOW if percent >= 50

  GREEN
end

def compact(tokens)
  return tokens.to_s if tokens < 1_000
  return format('%.1fk', tokens / 1_000.0).sub('.0k', 'k') if tokens < 1_000_000

  format('%.2fM', tokens / 1_000_000.0).sub('.00M', 'M')
end

def bar(percent)
  filled = (WIDTH * percent / 100.0).round.clamp(0, WIDTH)
  "#{color_for(percent)}#{FILLED * filled}#{DIM}#{EMPTY * (WIDTH - filled)}#{RESET}"
end

def duration(milliseconds)
  seconds = milliseconds.to_i / 1000
  format('%d:%02d', seconds / 60, seconds % 60)
end

input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end

cwd    = input.dig('workspace', 'current_dir') || input['cwd'] || Dir.pwd
window = input['context_window'] || {}
effort = input.dig('effort', 'level')

header = [
  "#{MAGENTA}#{File.basename(cwd)}#{RESET}",
  input.dig('model', 'display_name'),
  (effort && "#{effort} effort"),
  input.dig('output_style', 'name')
].compact
puts header.join("#{DIM} | #{RESET}")

used    = window['total_input_tokens'].to_i
size    = window['context_window_size'].to_i
percent = window['used_percentage'] || (size.positive? ? (used.to_f / size * 100).round : 0)

meter = [
  bar(percent),
  "#{color_for(percent)}#{percent.round}%#{RESET}",
  "#{DIM}ctx #{compact(used)}/#{compact(size)}#{RESET}",
  "#{DIM}#{duration(input.dig('cost', 'total_duration_ms'))}#{RESET}"
]
puts meter.join(' ')
