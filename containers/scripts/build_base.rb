#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the base image: rubies, node, the two agent CLIs, and the native
# libraries the subject apps need. Version pins live in lib/kit.rb.
#
#   ruby containers/scripts/build_base.rb [--tag llmx-base:latest] [--no-cache]

require_relative "lib/kit"

tag = Kit::BASE_IMAGE
no_cache = false

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--tag" then tag = args.shift
  when "--no-cache" then no_cache = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else
    abort "unknown option: #{arg}"
  end
end

Kit.ensure_builder_started!

build = [
  "container", "build",
  "--tag", tag,
  "--file", File.join(Kit::CONTAINERS_DIR, "base", "Containerfile"),
  "--build-arg", "RUBY_VERSIONS=#{Kit::PINS[:ruby_versions]}",
  "--build-arg", "NODE_VERSION=#{Kit::PINS[:node_version]}",
  "--build-arg", "CLAUDE_CODE_VERSION=#{Kit::PINS[:claude_code_version]}",
  "--build-arg", "CODEX_VERSION=#{Kit::PINS[:codex_version]}"
]
build << "--no-cache" if no_cache
build << File.join(Kit::CONTAINERS_DIR, "base")

Kit.log "building #{tag} (compiles #{Kit::PINS[:ruby_versions]} from source; expect 15-30 min cold)"
Kit.sh(*build)

Kit.log "smoke-checking the toolchain inside #{tag}"
check = <<~SH
  set -e
  echo "ruby:   $(ruby --version)"
  echo "node:   $(node --version)"
  echo "claude: $(claude --version)"
  echo "codex:  $(codex --version)"
  echo "vips:   $(vips --version)"
  echo "ffmpeg: $(ffmpeg -version | head -1)"
  echo "psql:   $(psql --version)"
  for v in #{Kit::PINS[:ruby_versions]}; do
    echo "ruby $v: $(mise exec ruby@$v -- ruby -e 'print RUBY_VERSION')"
  done
  cat /etc/llmx-versions.json
SH

Kit.sh("container", "run", "--rm", *Kit.run_args(mount_auth: false), tag, "bash", "-lc", check)

Kit.log "base image ready: #{tag}"
