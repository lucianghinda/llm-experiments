#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds llmx-base-opencode from llmx-base by adding one npm package.
#
#   ruby containers/scripts/build_opencode_image.rb
#
# Separate from build_base.rb because the base image compiles rubies from source
# and this does not, so this finishes in a minute or two and can be re-run
# without risking the expensive image.

require_relative "lib/kit"

Kit.ensure_builder_started!
Kit.ensure_disk_space!(need_gb: 5)

abort "base image #{Kit::BASE_IMAGE} not found; run build_base.rb first" unless Kit.image_exists?(Kit::BASE_IMAGE)

image = Kit::DERIVED_OPENCODE_IMAGE
Kit.log "building #{image} (opencode #{Kit::PINS[:opencode_version]})"

Kit.sh("container", "build",
       "--tag", image,
       "--build-arg", "BASE_IMAGE=#{Kit::BASE_IMAGE}",
       "--build-arg", "OPENCODE_VERSION=#{Kit::PINS[:opencode_version]}",
       "--file", File.join(Kit::CONTAINERS_DIR, "opencode", "Containerfile"),
       File.join(Kit::CONTAINERS_DIR, "opencode"))

out, ok = Kit.try("container", "run", "--rm", *Kit.run_args(memory: "2g", cpus: "2", mount_auth: false),
                  image, "bash", "-lc", "opencode --version")
abort "smoke check failed:\n#{out}" unless ok

Kit.log "ok: #{image} reports opencode #{out.strip.lines.last}"
