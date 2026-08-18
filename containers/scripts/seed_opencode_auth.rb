#!/usr/bin/env ruby
# frozen_string_literal: true

# Copies this machine's opencode credentials into the kit's credential store.
#
#   ruby containers/scripts/seed_opencode_auth.rb
#
# Claude and Codex get their container credentials from auth_setup.rb, which
# opens an interactive container and runs the normal login flow inside it. That
# is the better shape and opencode should get it too, but opencode keeps its
# credentials in XDG_DATA_HOME alongside its sessions and its database, so a
# login inside a container writes a whole state directory rather than one file.
#
# Until that is worked out, this copies the single credential file across. The
# file never leaves the machine: ~/.llmx/auth is outside the repository, is
# never baked into an image, and every trial copies it into a container-local
# directory rather than writing back to it.

require "fileutils"
require_relative "lib/kit"

SOURCE = File.expand_path(ENV.fetch("LLMX_OPENCODE_DATA", "~/.local/share/opencode"))
auth = File.join(SOURCE, "auth.json")

abort "no opencode credentials at #{auth}; run `opencode providers` and log in first" unless File.exist?(auth)

dest_dir = File.join(Kit::AUTH_DIR, "opencode")
FileUtils.mkdir_p(dest_dir)
dest = File.join(dest_dir, "auth.json")
FileUtils.cp(auth, dest)
FileUtils.chmod(0o600, dest)

Kit.log "seeded #{File.size(dest)} bytes into #{dest.sub(Dir.home, '~')}"
Kit.log "this file holds live tokens; it is gitignored by being outside the repository"
