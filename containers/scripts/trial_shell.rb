#!/usr/bin/env ruby
# frozen_string_literal: true

# Opens an interactive shell in a trial container, for when something fails and
# the transcript does not explain why.
#
#   ruby containers/scripts/trial_shell.rb --app campfire
#   ruby containers/scripts/trial_shell.rb --app campfire --branch exp/path-hints/bug-campfire-01-nat64-recheck
#   ruby containers/scripts/trial_shell.rb --base            # the base image, no app
#
# The container is disposable: it is removed on exit and nothing it writes
# reaches the host except through an explicitly mounted directory.

require_relative "lib/kit"

app_key = nil
branch = nil
use_base = false
mount = nil

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--app" then app_key = args.shift
  when "--branch" then branch = args.shift
  when "--base" then use_base = true
  when "--mount" then mount = args.shift
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

Kit.ensure_system_started!

image = use_base ? Kit::BASE_IMAGE : "llmx-app-#{app_key}:latest"
abort "--app or --base is required" if !use_base && app_key.nil?
abort "image #{image} not found; build it first" unless Kit.image_exists?(image)

extra = []
extra += ["--volume", "#{File.expand_path(mount)}:/mnt/host"] if mount

setup = +""
unless use_base
  apps = Kit.apps_config["apps"]
  app = apps.find { |a| a["key"] == app_key } or abort "unknown app: #{app_key}"
  # The agent-owned cluster at $PGDATA, as runner.rb starts it. `pg_ctlcluster`
  # reaches for the packaged system cluster, which needs root and is exactly the
  # one these images refuse to use; it silently never started.
  if app["database"] == "postgresql"
    setup << 'PGBIN=$(dirname $(ls /usr/lib/postgresql/*/bin/pg_ctl | head -1)); ' \
             '$PGBIN/pg_ctl -D "${PGDATA:-/home/agent/pgdata}" -l /tmp/postgres.log ' \
             "-o \"-p 5432\" -w start >/dev/null 2>&1 || true\n"
  end
  setup << "cd /workspace/app\n"
  setup << "git checkout #{branch} >/dev/null 2>&1\n" if branch
  setup << "git log --oneline -1\ngit status --short\n"
end
setup << "exec bash"

Kit.log "opening shell in #{image}#{branch ? " on #{branch}" : ''}"
system("container", "run", "--rm", "--interactive", "--tty",
       *Kit.run_args, *extra, image, "bash", "-lc", setup)
