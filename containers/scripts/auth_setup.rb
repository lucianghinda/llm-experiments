#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time interactive step: log the two agent CLIs in to the user's plan
# subscriptions, and keep the credentials in a directory that every later trial
# mounts read-write.
#
# Nothing is baked into an image and no API key is required. Re-run this when a
# refresh token expires; run_trial.rb stops with that instruction rather than
# burning trials against a dead login.
#
#   ruby containers/scripts/auth_setup.rb            # both CLIs
#   ruby containers/scripts/auth_setup.rb --agent codex
#   ruby containers/scripts/auth_setup.rb --verify   # check, log nothing in

require_relative "lib/kit"

agent = "both"
verify_only = false

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--agent" then agent = args.shift
  when "--verify" then verify_only = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

Kit.ensure_system_started!
abort "base image #{Kit::BASE_IMAGE} not found; run build_base.rb first" unless Kit.image_exists?(Kit::BASE_IMAGE)

VERIFY = <<~SH
  echo "--- claude ---"
  claude auth status 2>&1 | head -5 || echo "claude: no status subcommand on this build"
  echo "--- codex ---"
  codex login status 2>&1 | head -5 || echo "codex: not logged in"
SH

if verify_only
  Kit.sh("container", "run", "--rm", *Kit.run_args, Kit::BASE_IMAGE, "bash", "-lc", VERIFY)
  exit 0
end

puts <<~INTRO

  Logging the agent CLIs in to your plan subscriptions.

  A container will open with a shell. Run the login command(s) shown below and
  complete the browser device flow, then type `exit`.

  Credentials are written to #{Kit::AUTH_DIR} on this Mac and mounted into every
  trial. They never enter an image and are never committed.

INTRO

steps = []
steps << "claude    ->  run: claude   (then /login, complete the browser flow, then /exit)" if %w[both claude].include?(agent)
steps << "codex     ->  run: codex login" if %w[both codex].include?(agent)
puts steps.map { |s| "  #{s}" }.join("\n")
puts "\n  When both are done, type: exit\n\n"

shell = <<~SH
  echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
  echo "CODEX_HOME=$CODEX_HOME"
  echo
  exec bash
SH

# Interactive: hand the terminal to the container so the device flows work.
system("container", "run", "--rm", "--interactive", "--tty",
       *Kit.run_args, Kit::BASE_IMAGE, "bash", "-lc", shell)

puts "\nVerifying what persisted..."
Kit.sh("container", "run", "--rm", *Kit.run_args, Kit::BASE_IMAGE, "bash", "-lc", VERIFY,
       allow_failure: true)

claude_files = Dir.glob(File.join(Kit::AUTH_DIR, "claude", "**", "*")).size
codex_files = Dir.glob(File.join(Kit::AUTH_DIR, "codex", "**", "*")).size
puts "\n#{Kit::AUTH_DIR}: claude/ has #{claude_files} file(s), codex/ has #{codex_files} file(s)"
puts "If either is empty, the login did not persist - re-run this script."
