#!/usr/bin/env ruby
# frozen_string_literal: true

# Status line for the api-service project.
# One line, git flavoured: model | folder | branch + dirty | lines changed | cost

require 'json'
require 'shellwords'

RESET  = "\e[0m"
BOLD   = "\e[1m"
DIM    = "\e[2m"
CYAN   = "\e[36m"
GREEN  = "\e[32m"
RED    = "\e[31m"
YELLOW = "\e[33m"

def git(cwd, args)
  `cd #{cwd.shellescape} && git #{args} 2>/dev/null`.strip
end

def branch_segment(cwd)
  branch = git(cwd, 'rev-parse --abbrev-ref HEAD')
  return "#{DIM}no-git#{RESET}" if branch.empty?

  dirty = git(cwd, 'status --porcelain').empty? ? '' : "#{YELLOW}*#{RESET}"
  "#{GREEN}#{branch}#{RESET}#{dirty}"
end

def diff_segment(cost)
  added   = cost['total_lines_added'].to_i
  removed = cost['total_lines_removed'].to_i
  return nil if added.zero? && removed.zero?

  "#{GREEN}+#{added}#{RESET}#{DIM}/#{RESET}#{RED}-#{removed}#{RESET}"
end

def cost_segment(cost)
  usd = cost['total_cost_usd'].to_f
  return nil if usd.zero?

  format("#{DIM}$%.4f#{RESET}", usd)
end

input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end

cwd  = input.dig('workspace', 'current_dir') || input['cwd'] || Dir.pwd
cost = input['cost'] || {}

parts = [
  "#{CYAN}#{BOLD}#{input.dig('model', 'display_name') || 'claude'}#{RESET}",
  File.basename(cwd),
  branch_segment(cwd),
  diff_segment(cost),
  cost_segment(cost)
]

puts parts.compact.join("#{DIM} · #{RESET}")
