#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds one image holding both layout variants of an app, on top of the base
# image from containers/.
#
#   ruby convention-navigation/scripts/build_variant_image.rb --app campfire
#   ruby convention-navigation/scripts/build_variant_image.rb --app campfire --no-cache
#
# Both variants live in one image on purpose: they then share a byte-identical
# gem set, so a token difference between them cannot be a difference in what was
# installed.
#
# The gems are installed in their own layer, from Gemfile and Gemfile.lock
# alone, before any application source is copied. That ordering is what makes
# iterating on the scramble bearable: changing a move rule invalidates the
# source layer and rebuilds it in under a minute, while `bundle install` -- which
# for this app compiles native extensions and clones Rails from git -- stays
# cached. containers/scripts/build_app_image.rb copies source first and pays the
# full install on every edit.
#
# Images holding private code are never pushed to a registry.

require "fileutils"
require_relative "../../containers/scripts/lib/kit"

BRANCH_PREFIX = "exp/convention"
BUILD_ROOT = ENV.fetch("LLMX_BUILD_ROOT", "/tmp/llmx/build")

# What the branches are called inside the image. Deliberately opaque: an agent
# that read `trial/scrambled` in `git branch` would know the layout had been
# rearranged on purpose, which is a fact about the experiment rather than about
# the codebase. runner.rb renames whichever branch survives to `main`, so every
# trial sees the same name whatever the condition.
IMAGE_BRANCHES = {
  "conventional" => "trial/v1",
  "scrambled" => "trial/v2"
}.freeze

app_key = nil
no_cache = false

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--app" then app_key = args.shift
  when "--no-cache" then no_cache = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end
abort "--app is required" unless app_key

EXPERIMENT_DIR = File.expand_path("..", __dir__)
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
app = apps.find { |a| a["key"] == app_key } or abort "unknown app: #{app_key}"

repo = ENV["LLMX_APP_#{app_key.upcase}"]
abort "LLMX_APP_#{app_key.upcase} is not set" if repo.nil? || repo.empty?

Kit.ensure_disk_space!
Kit.ensure_builder_started!
abort "base image #{Kit::BASE_IMAGE} not found; run build_base.rb first" unless Kit.image_exists?(Kit::BASE_IMAGE)

source_branches = IMAGE_BRANCHES.keys.map { |v| "#{BRANCH_PREFIX}/#{v}" }
existing = Kit.capture("git", "-C", repo, "branch", "--list", "#{BRANCH_PREFIX}/*",
                       "--format=%(refname:short)").split("\n").map(&:strip).reject(&:empty?)
missing = source_branches - existing
abort "#{app_key}: missing branches #{missing.inspect}; run scramble.rb first" if missing.any?

context = File.join(BUILD_ROOT, "convention-#{app_key}")
FileUtils.rm_rf(context)
FileUtils.mkdir_p(context)

# Gemfile and Gemfile.lock are copied out of the conventional branch rather than
# off the host working tree, so the gems layer is built from committed content
# and cannot pick up an uncommitted local edit. The scramble never touches
# either file; scramble_check.rb proves it.
%w[Gemfile Gemfile.lock].each do |name|
  content = Kit.capture("git", "-C", repo, "show", "#{BRANCH_PREFIX}/conventional:#{name}")
  File.write(File.join(context, name), content)
end

bundle_path = File.join(context, "app.bundle")
Kit.log "bundling #{source_branches.size} branch(es) from #{app_key}"
Kit.sh("git", "-C", repo, "bundle", "create", bundle_path, *source_branches)
Kit.sh("git", "bundle", "verify", bundle_path)

# Cloning a bundle materialises only the checked-out branch locally; the rest
# arrive as origin/* refs, which disappear along with the remote.
localise = source_branches.map { |b| "git branch -f #{b} origin/#{b} 2>/dev/null || true;" }
                          .join(" \\\n      ")

# Each variant becomes one orphan commit with an identical message, so the
# history cannot say which variant this is, nor that a variant exists at all.
flatten = IMAGE_BRANCHES.map do |variant, target|
  "git checkout -q #{BRANCH_PREFIX}/#{variant}; git checkout -q --orphan #{target}; " \
    "git add -A; git commit -q -m 'Import application source';"
end.join(" \\\n      ")

drop_originals = source_branches.map { |b| "git branch -q -D #{b};" }.join(" ")

bundler_pin = app["bundler"] == "default" ? "" : "-v #{app['bundler']}"

containerfile = +<<~DOCKER
  FROM #{Kit::BASE_IMAGE}

  ARG APP_KEY
  ARG RUBY_VERSION

  ENV LLMX_APP=${APP_KEY} \\
      MISE_RUBY_VERSION=${RUBY_VERSION} \\
      RAILS_ENV=test

  USER agent
  WORKDIR /workspace

  # --- gems -----------------------------------------------------------------
  # Cached against Gemfile and Gemfile.lock alone. Nothing below this line can
  # invalidate it, which is the whole point of copying the source afterwards.
  COPY --chown=agent:agent Gemfile Gemfile.lock /workspace/gems/
  RUN set -eux; \\
      cd /workspace/gems; \\
      ruby --version; \\
      gem install bundler --no-document #{bundler_pin}; \\
      bundle install

  # --- source ---------------------------------------------------------------
  COPY --chown=agent:agent app.bundle /home/agent/app.bundle

  RUN set -eux; \\
      git clone --branch #{BRANCH_PREFIX}/conventional /home/agent/app.bundle /workspace/app; \\
      cd /workspace/app; \\
      #{localise} \\
      git remote remove origin; \\
      git config user.email dev@example.invalid; \\
      git config user.name Developer; \\
      #{flatten} \\
      #{drop_originals} \\
      git checkout -q #{IMAGE_BRANCHES['conventional']}; \\
      rm -f /home/agent/app.bundle; \\
      git reflog expire --expire=now --all; \\
      git gc --prune=now --quiet; \\
      git branch; \\
      test -z "$(git log --all --oneline --format='%s' | grep -viE '^Import application source$' || true)"
DOCKER

if app["database"] == "postgresql"
  # A private cluster owned by the agent user, not the packaged system cluster:
  # the system one needs root, and root is not something to hand a container
  # that runs model-authored shell commands. See build_app_image.rb for why the
  # socket directory has to move with it.
  containerfile << <<~DOCKER

    ENV PGDATA=/home/agent/pgdata \\
        PGHOST=127.0.0.1 \\
        PGPORT=5432 \\
        PGUSER=agent
    RUN set -eux; \\
        PGBIN=$(dirname $(ls /usr/lib/postgresql/*/bin/initdb | head -1)); \\
        echo "export PATH=$PGBIN:\\$PATH" >> /home/agent/.bashrc; \\
        $PGBIN/initdb -D $PGDATA -U agent --auth=trust --encoding=UTF8; \\
        echo "listen_addresses = '127.0.0.1'" >> $PGDATA/postgresql.conf; \\
        echo "unix_socket_directories = '/tmp'" >> $PGDATA/postgresql.conf; \\
        echo "fsync = off" >> $PGDATA/postgresql.conf; \\
        $PGBIN/pg_ctl -D $PGDATA -o "-p 5432" -w start; \\
        $PGBIN/createdb -U agent agent; \\
        $PGBIN/pg_ctl -D $PGDATA -w stop
  DOCKER
end

containerfile << <<~DOCKER

  # Bundler rewrites Gemfile.lock when the lockfile carries no entry for the
  # container's platform: these images are aarch64-linux, and an app locked only
  # on darwin and x86_64-linux gains an aarch64-linux line. That would leave the
  # tree dirty before any agent had touched it, so every trial would start with
  # a modified Gemfile.lock and carry it in the agent's own diff.
  #
  # The change is committed rather than reverted, because reverting invites
  # bundler to redo it mid-trial. It is amended onto each variant's single
  # commit so the "one commit called Import application source" property
  # survives, and the same lockfile is forced onto every branch so the two
  # variants stay byte-identical outside their own differences.
  RUN set -eux; \\
      cd /workspace/app; \\
      bundle install; \\
      if ! git diff --quiet; then \\
        git add -A; \\
        git commit -q --amend --no-edit; \\
        for b in $(git branch --format='%(refname:short)'); do \\
          if [ "$b" != #{IMAGE_BRANCHES['conventional']} ]; then \\
            git checkout -q "$b"; \\
            git checkout -q #{IMAGE_BRANCHES['conventional']} -- Gemfile.lock; \\
            git add -A; \\
            git commit -q --amend --no-edit; \\
            test -z "$(git status --porcelain)"; \\
          fi; \\
        done; \\
        git checkout -q #{IMAGE_BRANCHES['conventional']}; \\
        git reflog expire --expire=now --all; \\
        git gc --prune=now --quiet; \\
      fi; \\
      git status --porcelain; \\
      test -z "$(git status --porcelain)"; \\
      test -z "$(git log --all --oneline --format='%s' | grep -viE '^Import application source$' || true)"

  WORKDIR /workspace/app
DOCKER

File.write(File.join(context, "Containerfile"), containerfile)

tag = "llmx-conv-#{app_key}:latest"
build = ["container", "build", "--tag", tag,
         "--file", File.join(context, "Containerfile"),
         "--build-arg", "APP_KEY=#{app_key}",
         "--build-arg", "RUBY_VERSION=#{app['ruby']}"]
build << "--no-cache" if no_cache
build << context

Kit.log "building #{tag}"
Kit.sh(*build)

Kit.log "image ready: #{tag} (never push: #{app['privacy']} code)"
Kit.log "next: ruby convention-navigation/scripts/scramble_check.rb --app #{app_key}"
