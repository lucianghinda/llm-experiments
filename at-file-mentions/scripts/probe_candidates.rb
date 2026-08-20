#!/usr/bin/env ruby
# frozen_string_literal: true

# Finds fix commits that can still be planted.
#
# A commit is plantable when it changed both implementation and test files, and
# its implementation hunks still apply backwards to the experiment base branch.
# That second condition is the one that bites: a fix from months ago is useless
# if the file it touched has been rewritten since, because the lines the fix
# added are no longer there to remove.
#
# The script only reads and uses a scratch branch it cleans up after itself.
#
#   ruby at-file-mentions/scripts/probe_candidates.rb --app campfire
#   ruby at-file-mentions/scripts/probe_candidates.rb --app campfire --limit 600
#   ruby at-file-mentions/scripts/probe_candidates.rb --app campfire --sha e983e3f

require_relative "../../containers/scripts/lib/kit"

BRANCH_PREFIX = "exp/path-hints"
WORKTREE_ROOT = ENV.fetch("LLMX_PLANT_ROOT", "/tmp/llmx/plant")
SCRATCH = "#{BRANCH_PREFIX}/probe-scratch"

app_key = nil
limit = 400
only_shas = []
max_impl = 3

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--app" then app_key = args.shift
  when "--limit" then limit = args.shift.to_i
  when "--sha" then only_shas << args.shift
  when "--max-impl" then max_impl = args.shift.to_i
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

worktree = File.join(WORKTREE_ROOT, app_key)
abort "no worktree at #{worktree}; run plant.rb first" unless Dir.exist?(worktree)

base = "#{BRANCH_PREFIX}/base"

def test_file?(path)
  path.start_with?("test/", "spec/") || path.match?(/_(test|spec)\.rb\z/)
end

# Rails maps a test path onto an implementation path, so naming the failing
# test file - which every condition does, including cond-none - often names
# the defect file too. The agent only has to drop "test" and search, which is
# exactly what happened on the first cond-none trial: an opening
# `find . -name "*private_network*"` returned the implementation file before
# anything had been read.
#
# A bug whose implementation file is its test file's mirror therefore weakens
# the one condition it is supposed to stress. Flagged, not rejected: it is a
# reason to prefer another candidate, not a reason a commit cannot be planted.
def mirror_candidates(test_path)
  stem = test_path.sub(%r{\A(test|spec)/}, "").sub(/_(test|spec)\.rb\z/, "")
  ["#{stem}.rb", "app/#{stem}.rb", "lib/#{stem}.rb"]
end

def mirrored?(tests, impl)
  tests.any? { |t| (mirror_candidates(t) & impl).any? }
end

def changed_files(worktree, sha)
  Kit.capture("git", "-C", worktree, "show", "--name-only", "--format=", sha)
     .split("\n").map(&:strip).reject(&:empty?)
end

shas =
  if only_shas.any?
    only_shas.map { |s| Kit.capture("git", "-C", worktree, "rev-parse", s).strip }
  else
    Kit.capture("git", "-C", worktree, "log", "--format=%H", "-n", limit.to_s, app["base_sha"])
       .split("\n")
  end

Kit.log "probing #{shas.size} commit(s) in #{app_key}"

candidates = []

shas.each do |sha|
  files = changed_files(worktree, sha)
  next if files.empty?

  impl = files.reject { |f| test_file?(f) }
  tests = files.select { |f| test_file?(f) }
  next if impl.empty? || tests.empty?
  next if impl.size > max_impl
  next unless impl.all? { |f| f.end_with?(".rb") }

  # The file must still exist on base, or there is nothing to revert into.
  next unless impl.all? do |f|
    _, ok = Kit.try("git", "-C", worktree, "cat-file", "-e", "#{base}:#{f}")
    ok
  end

  patch = Kit.capture("git", "-C", worktree, "show", "--binary", sha, "--", *impl)
  next if patch.strip.empty?

  _, strict = Kit.try_input(patch, "git", "-C", worktree, "apply",
                            "--check", "--reverse", "--whitespace=nowarn")

  subject = Kit.capture("git", "-C", worktree, "log", "-1", "--format=%s", sha).strip
  stat = Kit.capture("git", "-C", worktree, "show", "--shortstat", "--format=", sha, "--", *impl).strip

  candidates << {
    sha: sha, subject: subject, impl: impl, tests: tests, strict: strict, stat: stat,
    mirrored: mirrored?(tests, impl)
  }
end

clean = candidates.select { |c| c[:strict] }
dirty = candidates.reject { |c| c[:strict] }

# Non-mirrored first: those are the ones that actually test cond-none.
clean = clean.sort_by { |c| c[:mirrored] ? 1 : 0 }
mirrored_count = clean.count { |c| c[:mirrored] }

puts "\n=== #{app_key}: #{clean.size} plantable / #{candidates.size} fix-shaped commits ==="
puts "    #{clean.size - mirrored_count} withhold the defect path from cond-none, #{mirrored_count} do not"
clean.each do |c|
  puts format("\n  %s  %s", c[:sha][0, 7], c[:subject][0, 78])
  puts format("    impl : %s", c[:impl].join(", "))
  puts format("    test : %s", c[:tests].join(", "))
  puts format("    size : %s", c[:stat])
  puts format("    note : implementation file is the test file's mirror, so cond-none is weakened") if c[:mirrored]
end

if clean.empty?
  puts "\n  none apply cleanly; the touched files have all been rewritten since"
end

puts "\n=== not plantable (impl rewritten since): #{dirty.size} ==="
dirty.first(15).each { |c| puts format("  %s  %s", c[:sha][0, 7], c[:subject][0, 78]) }
