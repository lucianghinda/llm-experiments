#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the variant branches in the subject app repo.
#
#   exp/convention/conventional   the app as its authors wrote it, with the
#                                 agent instruction files deleted so no app gets
#                                 to coach the agent under test
#   exp/convention/scrambled      the same code in a non-conventional layout:
#                                 roots moved, tests un-mirrored, routes split,
#                                 everything wired through configuration
#
# Both branches are local and never pushed. Work happens in a throwaway worktree
# so the user's own checkout is never touched, not even its branch.
#
#   ruby convention-navigation/scripts/scramble.rb
#   ruby convention-navigation/scripts/scramble.rb --app campfire --force
#   ruby convention-navigation/scripts/scramble.rb --status
#
# The scramble moves files and writes the handful of wiring files listed in
# scramble.yml. It never edits a line of application code, which is what makes
# a measured difference attributable to path knowledge rather than to
# searchability: `grep "def deliver"` returns the same thing on both branches.
# scramble_check.rb is what proves that claim rather than asserting it.

require "fileutils"
require "json"
require_relative "../../containers/scripts/lib/kit"

BRANCH_PREFIX = "exp/convention"
WORKTREE_ROOT = ENV.fetch("LLMX_SCRAMBLE_ROOT", File.expand_path("~/.llmx/scramble"))

# One of the subject apps installs a pre-commit hook that rejects the deletions
# the conventional branch has to make. Repository hooks are host-only: a git
# bundle does not carry them, so no trial ever sees one.
NO_VERIFY = "--no-verify"

only_app = nil
status_only = false
force = false

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--app" then only_app = args.shift
  when "--status" then status_only = true
  when "--force" then force = true
  when "-h", "--help"
    puts File.read(__FILE__).lines.grep(/\A#/).join
    exit 0
  else abort "unknown option: #{arg}"
  end
end

EXPERIMENT_DIR = File.expand_path("..", __dir__)
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
scrambles = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "scramble.yml"))["scrambles"]

def host_path_for(app)
  var = "LLMX_APP_#{app['key'].upcase}"
  path = ENV[var]
  abort "#{var} is not set. See convention-navigation/apps.local.example" if path.nil? || path.empty?
  abort "#{var} points at #{path}, which is not a git repo" unless Dir.exist?(File.join(path, ".git"))

  path
end

def branch_exists?(repo, name)
  Kit.capture("git", "-C", repo, "rev-parse", "--verify", "--quiet", "refs/heads/#{name}",
              allow_failure: true).strip != ""
end

def ensure_worktree(repo, app_key, base_sha)
  dir = File.join(WORKTREE_ROOT, app_key)
  if Dir.exist?(dir)
    Kit.log "reusing worktree #{dir}"
    return dir
  end

  FileUtils.mkdir_p(WORKTREE_ROOT)
  Kit.log "adding worktree #{dir}"
  Kit.sh("git", "-C", repo, "worktree", "add", "--detach", dir, base_sha)
  dir
end

# The conventional branch is not the app untouched: it is the app with its agent
# instruction files removed. Leaving a CLAUDE.md in place would let the app tell
# the agent where things are, which is the variable under test.
def build_conventional(worktree, app)
  branch = "#{BRANCH_PREFIX}/conventional"
  Kit.sh("git", "-C", worktree, "checkout", "-B", branch, app["base_sha"])
  Kit.sh("git", "-C", worktree, "reset", "--hard", app["base_sha"])
  Kit.sh("git", "-C", worktree, "clean", "-fdq")

  present = Array(app["neutralize"]).select { |p| File.exist?(File.join(worktree, p)) }
  if present.empty?
    Kit.log "#{app['key']}: no agent instruction files to remove"
    Kit.sh("git", "-C", worktree, "commit", NO_VERIFY, "--allow-empty", "-m",
           "experiment base: no agent instruction files present")
  else
    Kit.sh("git", "-C", worktree, "rm", "-r", "-q", "--", *present)
    Kit.sh("git", "-C", worktree, "commit", NO_VERIFY, "-m", <<~MSG)
      experiment base: remove agent instruction files

      Deleted so an agent under test reads only the code, not the
      repository's own guidance about how to work on it:
      #{present.map { |p| "  #{p}" }.join("\n")}
    MSG
  end
  branch
end

def files_under(worktree, relative)
  Kit.capture("git", "-C", worktree, "ls-files", "--", relative)
     .split("\n").map(&:strip).reject(&:empty?)
end

# A root move is `git mv` of a whole directory. Everything below it keeps its
# relative path, because every directory below an autoload root is a Ruby
# namespace and renaming one would rename a constant.
def move_root(worktree, from, to, manifest)
  source = File.join(worktree, from)
  target = File.join(worktree, to)
  abort "scramble: #{from} does not exist in #{worktree}" unless Dir.exist?(source)
  abort "scramble: #{to} already exists; refusing to merge two trees" if File.exist?(target)

  before = files_under(worktree, from)
  abort "scramble: #{from} is tracked but empty" if before.empty?

  FileUtils.mkdir_p(File.dirname(target))
  Kit.sh("git", "-C", worktree, "mv", from, to)

  before.each do |path|
    manifest[path] = path.sub(/\A#{Regexp.escape(from)}(?=\/)/, to)
  end
  before.size
end

def apply_wiring(worktree, app_key, wiring, experiment_dir)
  source_root = File.join(experiment_dir, "variants", app_key, "scrambled")
  abort "scramble: no wiring directory at #{source_root}" unless Dir.exist?(source_root)

  # Every file shipped under variants/<app>/scrambled/ must be declared in
  # scramble.yml, and every declared file must exist. Either mismatch means the
  # check script would compare the wrong set of files and pass a scramble that
  # silently edited application code.
  shipped = Dir.glob(File.join(source_root, "**", "*"))
               .select { |p| File.file?(p) }
               .map { |p| p.sub(source_root + "/", "") }
               .sort
  declared = Array(wiring).sort
  if shipped != declared
    abort <<~MSG
      scramble: variants/#{app_key}/scrambled/ and scramble.yml disagree.

        only on disk    : #{(shipped - declared).inspect}
        only in the yml : #{(declared - shipped).inspect}
    MSG
  end

  shipped.each do |rel|
    target = File.join(worktree, rel)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(source_root, rel), target)
  end
  shipped
end

def build_scrambled(worktree, app, spec, experiment_dir)
  branch = "#{BRANCH_PREFIX}/scrambled"
  conventional = "#{BRANCH_PREFIX}/conventional"

  Kit.sh("git", "-C", worktree, "checkout", "-B", branch, conventional)
  Kit.sh("git", "-C", worktree, "reset", "--hard", conventional)
  Kit.sh("git", "-C", worktree, "clean", "-fdq")

  manifest = {}
  moved = 0
  Array(spec["roots"]).each do |rule|
    moved += move_root(worktree, rule["from"], rule["to"], manifest)
    Kit.log "  #{rule['from']} -> #{rule['to']}"
  end
  Array(spec["tests"]).each do |rule|
    moved += move_root(worktree, rule["from"], rule["to"], manifest)
    Kit.log "  #{rule['from']} -> #{rule['to']}"
  end

  wiring = apply_wiring(worktree, app["key"], spec["wiring"], experiment_dir)
  Kit.log "  wrote #{wiring.size} wiring file(s)"

  # Every autoload root named in scramble.yml has to be a real directory now.
  # An unregistered concerns/ directory does not fail loudly: Zeitwerk reads it
  # as a namespace and every constant inside moves under Concerns::, which
  # surfaces later as an unrelated NameError.
  missing = Array(spec["autoload_roots"]).reject { |rel| Dir.exist?(File.join(worktree, rel)) }
  abort "scramble: autoload roots missing after the move: #{missing.inspect}" if missing.any?

  Kit.sh("git", "-C", worktree, "add", "-A")
  Kit.sh("git", "-C", worktree, "commit", NO_VERIFY, "-m", <<~MSG)
    experiment variant: non-conventional source layout

    Moves the framework's default roots and splits the route table. No class,
    module, method or constant is renamed, and no file's contents change except
    the wiring files:
    #{wiring.map { |w| "  #{w}" }.join("\n")}
  MSG

  { branch: branch, manifest: manifest, moved: moved, wiring: wiring }
end

results = []

apps.each do |app|
  next if only_app && app["key"] != only_app

  repo = host_path_for(app)

  if status_only
    branches = Kit.capture("git", "-C", repo, "branch", "--list", "#{BRANCH_PREFIX}/*",
                           "--format=%(refname:short) %(objectname:short)").strip
    puts "  #{app['key']}:"
    puts(branches.empty? ? "    (no variant branches)" : branches.lines.map { |l| "    #{l.strip}" }.join("\n"))
    next
  end

  spec = scrambles[app["key"]]
  abort "scramble.yml has no entry for #{app['key']}" unless spec

  puts "\n=== #{app['key']} ==="

  if branch_exists?(repo, "#{BRANCH_PREFIX}/scrambled") && !force
    Kit.log "#{app['key']}: variant branches already exist, skipping (use --force to rebuild)"
    results << { app: app["key"], skipped: true }
    next
  end

  worktree = ensure_worktree(repo, app["key"], app["base_sha"])
  build_conventional(worktree, app)
  Kit.log "#{app['key']}: conventional branch ready"

  outcome = build_scrambled(worktree, app, spec, EXPERIMENT_DIR)
  Kit.log "#{app['key']}: scrambled branch ready (#{outcome[:moved]} file(s) moved)"

  # The manifest lives here, not in the app. It is what scramble_check.rb reads
  # to prove that a moved file's contents did not change, and an agent that
  # found it inside the checkout would be handed the whole layout for free.
  manifest_path = File.join(EXPERIMENT_DIR, "variants", app["key"], "manifest.json")
  FileUtils.mkdir_p(File.dirname(manifest_path))
  File.write(manifest_path, JSON.pretty_generate(
                              "app" => app["key"],
                              "base_sha" => app["base_sha"],
                              "conventional_branch" => "#{BRANCH_PREFIX}/conventional",
                              "scrambled_branch" => outcome[:branch],
                              "wiring" => outcome[:wiring],
                              "autoload_roots" => Array(spec["autoload_roots"]),
                              "moves" => outcome[:manifest]
                            ))
  Kit.log "#{app['key']}: wrote #{manifest_path.sub(Kit::ROOT + '/', '')}"

  # Leave the worktree on the conventional branch so a stray later command
  # cannot land on the scrambled one.
  Kit.sh("git", "-C", worktree, "checkout", "#{BRANCH_PREFIX}/conventional")
  results << { app: app["key"], moved: outcome[:moved], wiring: outcome[:wiring].size }
end

exit 0 if status_only

puts "\n=== summary ==="
results.each do |r|
  puts(r[:skipped] ? format("  %-18s skipped", r[:app])
                   : format("  %-18s %d file(s) moved, %d wiring file(s)", r[:app], r[:moved], r[:wiring]))
end
puts "\nNothing was pushed; every branch is local."
puts "next: ruby convention-navigation/scripts/build_variant_image.rb --app campfire"
puts "      ruby convention-navigation/scripts/scramble_check.rb --app campfire"
