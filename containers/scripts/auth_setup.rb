#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time interactive step: log the agent CLIs in to the user's plan
# subscriptions, and keep the credentials in a directory that every later trial
# mounts read-write.
#
# Nothing is baked into an image and no API key is required. Re-run this when a
# refresh token expires; run_trial.rb stops with that instruction rather than
# burning trials against a dead login.
#
# Claude and Codex are pointed at the credential store through CLAUDE_CONFIG_DIR
# and CODEX_HOME, so their logins land there directly. opencode takes no such
# variable: it keeps credentials in XDG_DATA_HOME next to its sessions and its
# database, so logging in writes a whole state directory. This points
# XDG_DATA_HOME at a container-local directory that dies with the container and
# copies out the one credential file afterwards, which gets opencode the same
# shape as the other two without carrying its session store along.
#
#   ruby containers/scripts/auth_setup.rb            # all three CLIs
#   ruby containers/scripts/auth_setup.rb --agent codex
#   ruby containers/scripts/auth_setup.rb --agent opencode
#   ruby containers/scripts/auth_setup.rb --verify   # check, log nothing in

require_relative "lib/kit"

AGENTS = %w[claude codex opencode].freeze

agent = "all"
verify_only = false

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--agent"
  agent = args.shift
  abort "unknown agent: #{agent}" unless AGENTS.include?(agent)
  when "--verify" then verify_only = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

Kit.ensure_system_started!
abort "base image #{Kit::BASE_IMAGE} not found; run build_base.rb first" unless Kit.image_exists?(Kit::BASE_IMAGE)

# Whichever image carries opencode, so one shell can log all three in. On a base
# built before opencode was folded in, this is the derived image.
IMAGE = Kit.opencode_image
abort "image #{IMAGE} not found; run build_base.rb (or build_opencode_image.rb)" unless Kit.image_exists?(IMAGE)

# opencode's credentials live in XDG_DATA_HOME with its sessions and database,
# so the login runs against a directory inside the container and only auth.json
# is copied back out to the mounted store.
OPENCODE_LOGIN_HOME = "/home/#{Kit::AGENT_USER}/.opencode-login"
OPENCODE_AUTH_OUT = "/home/#{Kit::AGENT_USER}/.agent-auth/opencode/auth.json"

VERIFY = <<~SH
  echo "--- claude ---"
  claude auth status 2>&1 | head -5 || echo "claude: no status subcommand on this build"
  echo "--- codex ---"
  codex login status 2>&1 | head -5 || echo "codex: not logged in"
  echo "--- opencode ---"
  if [ -s "#{OPENCODE_AUTH_OUT}" ]; then
    echo "opencode: auth.json present ($(wc -c < "#{OPENCODE_AUTH_OUT}") bytes)"
  else
    echo "opencode: no credential file in the store"
  fi
SH

if verify_only
  Kit.sh("container", "run", "--rm", *Kit.run_args, IMAGE, "bash", "-lc", VERIFY)
  exit 0
end

puts <<~INTRO

  Logging the agent CLIs in to your plan subscriptions.

  A container will open with a shell. Run the login command(s) shown below and
  complete the browser device flow, then type `exit`.

  Credentials are written to #{Kit::AUTH_DIR} on this Mac and mounted into every
  trial. They never enter an image and are never committed.

INTRO

wanted = agent == "all" ? AGENTS : [agent]

steps = []
steps << "claude    ->  run: claude   (then /login, complete the browser flow, then /exit)" if wanted.include?("claude")
steps << "codex     ->  run: codex login" if wanted.include?("codex")
steps << "opencode  ->  run: opencode auth login" if wanted.include?("opencode")
puts steps.map { |s| "  #{s}" }.join("\n")
puts "\n  When you are done, type: exit\n\n"

# `exec bash` would replace this shell and the copy-out would never run, so the
# shell is called and the file is moved after it returns.
shell = <<~SH
  export XDG_DATA_HOME=#{OPENCODE_LOGIN_HOME}
  mkdir -p "$XDG_DATA_HOME"
  echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
  echo "CODEX_HOME=$CODEX_HOME"
  echo "XDG_DATA_HOME=$XDG_DATA_HOME  (opencode; dies with this container)"
  echo
  bash
  if [ -s "$XDG_DATA_HOME/opencode/auth.json" ]; then
    mkdir -p "$(dirname #{OPENCODE_AUTH_OUT})"
    cp "$XDG_DATA_HOME/opencode/auth.json" "#{OPENCODE_AUTH_OUT}"
    chmod 600 "#{OPENCODE_AUTH_OUT}"
    echo "copied opencode auth.json into the credential store"
  fi
SH

# Interactive: hand the terminal to the container so the device flows work.
system("container", "run", "--rm", "--interactive", "--tty",
       *Kit.run_args, IMAGE, "bash", "-lc", shell)

puts "\nVerifying what persisted..."
Kit.sh("container", "run", "--rm", *Kit.run_args, IMAGE, "bash", "-lc", VERIFY,
       allow_failure: true)

counts = AGENTS.map do |name|
  "#{name}/ has #{Dir.glob(File.join(Kit::AUTH_DIR, name, '**', '*')).size} file(s)"
end
puts "\n#{Kit::AUTH_DIR}: #{counts.join(', ')}"
puts "If one is empty, that login did not persist - re-run this script for it."
puts "For opencode, seed_opencode_auth.rb still copies this machine's file across."
