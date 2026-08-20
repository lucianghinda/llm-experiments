#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates the experiment branches in the subject app repos.
#
# Two kinds of branch, both local and never pushed:
#
#   exp/path-hints/base           forked from apps.yml base_sha, with one commit
#                                 deleting the agent instruction files so no app
#                                 gets to coach the agent under test
#   exp/path-hints/bug-<id>       forked from base, with one commit that reverts
#                                 the implementation hunks of a real fix commit
#                                 while keeping that commit's regression test
#
# Work happens in a throwaway worktree so the user's own checkout is never
# touched, not even its branch.
#
#   ruby at-file-mentions/scripts/plant.rb            # all apps, all bugs
#   ruby at-file-mentions/scripts/plant.rb --app campfire
#   ruby at-file-mentions/scripts/plant.rb --status   # report, change nothing

require "fileutils"
require_relative "../../containers/scripts/lib/kit"

BRANCH_PREFIX = "exp/path-hints"
WORKTREE_ROOT = ENV.fetch("LLMX_PLANT_ROOT", "/tmp/llmx/plant")

# One app installs a pre-commit hook that rejects the very deletions the base
# branch has to make. Repository hooks are host-only anyway: a git bundle does
# not carry them, so no trial ever sees one.
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
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]

def host_path_for(app)
  var = "LLMX_APP_#{app['key'].upcase}"
  path = ENV[var]
  abort "#{var} is not set. See at-file-mentions/apps.local.example" if path.nil? || path.empty?
  abort "#{var} points at #{path}, which is not a git repo" unless Dir.exist?(File.join(path, ".git"))
  path
end

def git(repo, *cmd, allow_failure: false)
  Kit.capture("git", "-C", repo, *cmd, allow_failure: allow_failure)
end

def branch_exists?(repo, name)
  Kit.capture("git", "-C", repo, "rev-parse", "--verify", "--quiet", "refs/heads/#{name}",
              allow_failure: true).strip != ""
end

# A worktree lets us build branches without disturbing the checkout the user is
# sitting in, which for two of these repos is a feature branch with local edits.
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

def plant_base(worktree, app)
  branch = "#{BRANCH_PREFIX}/base"
  # Hard reset first: a failed planting attempt can leave edits in the worktree,
  # and without this they get swept into the base commit, which would put the
  # bug into every branch instead of one.
  Kit.sh("git", "-C", worktree, "checkout", "-B", branch, app["base_sha"])
  Kit.sh("git", "-C", worktree, "reset", "--hard", app["base_sha"])

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

# Undo the fix while keeping its regression test.
#
# Reverting the whole commit and restoring the test afterwards looks simpler but
# fails: the test files of these commits have been edited since, so the revert
# conflicts inside a file we were going to throw away anyway. Applying the fix's
# diff backwards, restricted to the implementation files, never reads the test.
def plant_bug(worktree, bug)
  branch = "#{BRANCH_PREFIX}/bug-#{bug['id']}-#{bug['slug']}"
  base = "#{BRANCH_PREFIX}/base"
  sha = bug["fix_sha"]
  impl = Array(bug["impl_files"])

  _, is_ancestor = Kit.try("git", "-C", worktree, "merge-base", "--is-ancestor", sha, base)
  unless is_ancestor
    return { branch: branch, ok: false, error: "#{sha[0, 7]} is not an ancestor of #{base}" }
  end

  Kit.sh("git", "-C", worktree, "checkout", "-B", branch, base)
  Kit.sh("git", "-C", worktree, "reset", "--hard", base)

  patch = Kit.capture("git", "-C", worktree, "show", "--binary", sha, "--", *impl)
  if patch.strip.empty?
    Kit.sh("git", "-C", worktree, "checkout", base)
    return { branch: branch, ok: false, error: "#{sha[0, 7]} touches none of #{impl.inspect}" }
  end

  out, applied = Kit.try_input(patch, "git", "-C", worktree, "apply",
                               "--reverse", "--3way", "--whitespace=nowarn")
  unless applied
    Kit.sh("git", "-C", worktree, "checkout", "-f", base)
    return { branch: branch, ok: false, error: "reverse patch failed:\n#{out}" }
  end

  Kit.sh("git", "-C", worktree, "add", "--", *impl)
  changed = Kit.capture("git", "-C", worktree, "diff", "--cached", "--name-only").split("\n")
  expected = impl.sort
  if changed.sort != expected
    Kit.sh("git", "-C", worktree, "checkout", "-f", base)
    return { branch: branch, ok: false,
             error: "staged #{changed.inspect}, expected only #{expected.inspect}" }
  end

  Kit.sh("git", "-C", worktree, "commit", NO_VERIFY, "-m", <<~MSG)
    plant #{bug['id']}: reintroduce the defect fixed in #{sha[0, 7]}

    Reverts only the implementation hunks of that commit. Its regression
    test is kept, so #{bug['test_file']} now fails the way it did before
    the fix landed.
  MSG

  { branch: branch, ok: true }
end

def report(repo, app_key)
  branches = Kit.capture("git", "-C", repo, "branch", "--list", "#{BRANCH_PREFIX}/*",
                         "--format=%(refname:short) %(objectname:short)").strip
  puts "  #{app_key}:"
  if branches.empty?
    puts "    (no experiment branches)"
  else
    branches.each_line { |line| puts "    #{line.strip}" }
  end
end

results = []

apps.each do |app|
  next if only_app && app["key"] != only_app

  repo = host_path_for(app)

  if status_only
    report(repo, app["key"])
    next
  end

  puts "\n=== #{app['key']} ==="

  if branch_exists?(repo, "#{BRANCH_PREFIX}/base") && !force
    Kit.log "#{app['key']}: #{BRANCH_PREFIX}/base already exists, skipping (use --force to rebuild)"
  else
    worktree = ensure_worktree(repo, app["key"], app["base_sha"])
    plant_base(worktree, app)
    Kit.log "#{app['key']}: base branch ready"
  end

  worktree = ensure_worktree(repo, app["key"], app["base_sha"])

  bugs.select { |b| b["app"] == app["key"] }.each do |bug|
    branch = "#{BRANCH_PREFIX}/bug-#{bug['id']}-#{bug['slug']}"
    if branch_exists?(repo, branch) && !force
      Kit.log "#{bug['id']}: already planted, skipping"
      results << { id: bug["id"], ok: true, skipped: true }
      next
    end

    outcome = plant_bug(worktree, bug)
    results << outcome.merge(id: bug["id"])
    if outcome[:ok]
      Kit.log "#{bug['id']}: planted on #{outcome[:branch]}"
    else
      warn "[kit] #{bug['id']}: FAILED - #{outcome[:error]}"
    end
  end

  # Leave the worktree on base so a stray later command cannot land on a bug branch.
  Kit.sh("git", "-C", worktree, "checkout", "#{BRANCH_PREFIX}/base")

  # Drop bug branches that bugs.yml no longer describes. Renaming a bug's slug
  # or swapping its fix commit otherwise leaves a branch behind that still looks
  # runnable, and a trial pointed at it would measure a bug nobody chose.
  expected = bugs.select { |b| b["app"] == app["key"] }
                 .map { |b| "#{BRANCH_PREFIX}/bug-#{b['id']}-#{b['slug']}" }
  actual = Kit.capture("git", "-C", repo, "branch", "--list", "#{BRANCH_PREFIX}/bug-*",
                       "--format=%(refname:short)").split("\n").map(&:strip).reject(&:empty?)
  (actual - expected).each do |stale|
    Kit.log "#{app['key']}: pruning stale branch #{stale}"
    Kit.sh("git", "-C", repo, "branch", "-D", stale)
  end
end

exit 0 if status_only

puts "\n=== summary ==="
results.each do |r|
  state = if r[:skipped] then "skipped"
          elsif r[:ok] then "planted"
          else "FAILED"
          end
  puts format("  %-22s %s", r[:id], state)
end

failed = results.reject { |r| r[:ok] }
abort "\n#{failed.size} bug(s) failed to plant" unless failed.empty?
puts "\nAll bugs planted. Nothing was pushed; every branch is local."
