#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds a per-app image on top of the base image, so a trial starts instantly
# instead of paying for `bundle install` and database setup every time.
#
# The app arrives as a git bundle containing only the experiment branches. That
# matters: a bundle carries committed history and nothing else, so untracked
# secrets, stale local bundler overrides and repository hooks on the host can
# never reach the image.
#
# The image also strips the repository of anything that would let an agent read
# the answer instead of finding it. See FLATTENING below.
#
#   ruby containers/scripts/build_app_image.rb --app campfire
#   ruby containers/scripts/build_app_image.rb --app campfire --no-cache
#
# Images holding private code are never pushed to a registry.

require "fileutils"
require_relative "lib/kit"

BRANCH_PREFIX = "exp/path-hints"
BUILD_ROOT = ENV.fetch("LLMX_BUILD_ROOT", "/tmp/llmx/build")

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

EXPERIMENT_DIR = File.join(Kit::ROOT, "at-file-mentions")
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]
app = apps.find { |a| a["key"] == app_key } or abort "unknown app: #{app_key}"

repo = ENV["LLMX_APP_#{app_key.upcase}"]
abort "LLMX_APP_#{app_key.upcase} is not set" if repo.nil? || repo.empty?

Kit.ensure_disk_space!
Kit.ensure_builder_started!
abort "base image #{Kit::BASE_IMAGE} not found; run build_base.rb first" unless Kit.image_exists?(Kit::BASE_IMAGE)

context = File.join(BUILD_ROOT, app_key)
FileUtils.rm_rf(context)
FileUtils.mkdir_p(context)

app_bugs = bugs.select { |b| b["app"] == app_key }
abort "#{app_key}: no bugs in bugs.yml" if app_bugs.empty?

# FLATTENING
#
# Each experiment branch becomes one orphan commit called "Import application
# source", renamed to an opaque `trial/<bug id>`.
#
# Three leaks close here, all of which would let an agent read the answer rather
# than search for it:
#
#   the commit message  said "reintroduce the defect fixed in <sha>"
#   the commit diff     was the real fix, inverted
#   the branch name     carried the defect's slug, e.g. -nat64-recheck
#
# Leaks like these do not just add noise, they bias: an agent given no path is
# far likelier to go digging through history than one handed the path outright,
# so the shortcut would help exactly the condition the experiment expects to be
# slowest. run_trial.rb closes the fourth leak by deleting every branch except
# the one under test, so `git diff trial/base` cannot reveal it either.
branch_map = { "#{BRANCH_PREFIX}/base" => "trial/base" }
app_bugs.each do |bug|
  branch_map["#{BRANCH_PREFIX}/bug-#{bug['id']}-#{bug['slug']}"] = "trial/#{bug['id']}"
end

branches = Kit.capture("git", "-C", repo, "branch", "--list", "#{BRANCH_PREFIX}/*",
                       "--format=%(refname:short)").split("\n").map(&:strip).reject(&:empty?)
missing = branch_map.keys - branches
abort "#{app_key}: missing branches #{missing.inspect}; run plant.rb first" if missing.any?

bundle_path = File.join(context, "app.bundle")
Kit.log "bundling #{branch_map.size} branch(es) from #{app_key}"
Kit.sh("git", "-C", repo, "bundle", "create", bundle_path, *branch_map.keys)
Kit.sh("git", "bundle", "verify", bundle_path)

# Cloning a bundle materialises only the checked-out branch locally; the rest
# arrive as origin/* refs, which disappear along with the remote. Create real
# local branches first, then drop the remote.
localise = branch_map.keys.map { |b| "git branch -f #{b} origin/#{b} 2>/dev/null || true;" }
                     .join(" \\\n      ")

flatten = branch_map.map do |source, target|
  "git checkout -q #{source}; git checkout -q --orphan #{target}; " \
    "git add -A; git commit -q -m 'Import application source';"
end.join(" \\\n      ")

drop_originals = branch_map.keys.map { |b| "git branch -q -D #{b};" }.join(" ")

containerfile = +<<~DOCKER
  FROM #{Kit::BASE_IMAGE}

  ARG APP_KEY
  ARG RUBY_VERSION

  ENV LLMX_APP=${APP_KEY} \\
      MISE_RUBY_VERSION=${RUBY_VERSION} \\
      RAILS_ENV=test

  USER agent
  WORKDIR /workspace

  COPY --chown=agent:agent app.bundle /home/agent/app.bundle

  RUN set -eux; \\
      git clone --branch #{BRANCH_PREFIX}/base /home/agent/app.bundle /workspace/app; \\
      cd /workspace/app; \\
      #{localise} \\
      git remote remove origin; \\
      git config user.email dev@example.invalid; \\
      git config user.name Developer; \\
      #{flatten} \\
      #{drop_originals} \\
      git checkout -q trial/base; \\
      rm -f /home/agent/app.bundle; \\
      git reflog expire --expire=now --all; \\
      git gc --prune=now --quiet; \\
      git branch; \\
      test -z "$(git log --all --oneline --format='%s' | grep -viE '^Import application source$' || true)"

  WORKDIR /workspace/app
DOCKER

if app["database"] == "postgresql"
  # A private cluster owned by the agent user, not the packaged system cluster.
  # The system one needs root to start, root is not available mid-trial, and
  # installing sudo just to reach it would put a privilege-escalation path in a
  # container that runs a model's shell commands. initdb as `agent` makes agent
  # the superuser and pg_ctl needs no privileges at all.
  #
  # The socket directory has to move with it. Postgres creates a Unix socket at
  # startup even when every client speaks TCP, and its default
  # /var/run/postgresql belongs to the postgres system user, so an agent-owned
  # cluster dies on the spot with "could not create lock file ... Permission
  # denied" - the one privilege the design set out to avoid needing. /tmp is
  # agent-writable, and nothing here uses the socket anyway: PGHOST is
  # 127.0.0.1 and listen_addresses matches.
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

  # Gems install to BUNDLE_PATH from the base image, which is outside the
  # checkout, so `git status` during a trial shows only the agent's own edits.
  #
  # Bundler rewrites Gemfile.lock when the lockfile has no entry for the
  # container's platform: these images are aarch64-linux, and an app locked only
  # on darwin and x86_64-linux gains an aarch64-linux line during install. That
  # leaves the tree dirty before any agent has touched it, so every trial would
  # start with a modified Gemfile.lock and carry it in the agent's own diff.
  #
  # The lockfile change is committed rather than reverted. Reverting invites
  # bundler to redo it mid-trial, which would dirty the tree at a point that
  # actually matters. It is amended onto each branch's single commit so the
  # "one commit called Import application source" property survives, and the
  # working tree carries the same change across every checkout because the
  # planted bugs only ever touch implementation files.
  RUN set -eux; \\
      cd /workspace/app; \\
      ruby --version; \\
      gem install bundler --no-document #{app['bundler'] == 'default' ? '' : "-v #{app['bundler']}"}; \\
      bundle install; \\
      if ! git diff --quiet; then \\
        git add -A; \\
        git commit -q --amend --no-edit; \\
        for b in $(git branch --format='%(refname:short)'); do \\
          if [ "$b" != trial/base ]; then \\
            git checkout -q "$b"; \\
            git checkout -q trial/base -- Gemfile.lock; \\
            git add -A; \\
            git commit -q --amend --no-edit; \\
            test -z "$(git status --porcelain)"; \\
          fi; \\
        done; \\
        git checkout -q trial/base; \\
        git reflog expire --expire=now --all; \\
        git gc --prune=now --quiet; \\
      fi; \\
      git status --porcelain; \\
      test -z "$(git status --porcelain)"; \\
      test -z "$(git log --all --oneline --format='%s' | grep -viE '^Import application source$' || true)"
DOCKER

File.write(File.join(context, "Containerfile"), containerfile)

tag = "llmx-app-#{app_key}:latest"
build = ["container", "build", "--tag", tag,
         "--file", File.join(context, "Containerfile"),
         "--build-arg", "APP_KEY=#{app_key}",
         "--build-arg", "RUBY_VERSION=#{app['ruby']}"]
build << "--no-cache" if no_cache
build << context

Kit.log "building #{tag}"
Kit.sh(*build)

Kit.log "app image ready: #{tag} (never push: #{app['privacy']} code)"
