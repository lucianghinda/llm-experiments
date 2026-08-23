#!/usr/bin/env ruby
# frozen_string_literal: true

# Proves the scramble moved files and changed nothing else.
#
#   ruby convention-navigation/scripts/scramble_check.rb --app campfire
#   ruby convention-navigation/scripts/scramble_check.rb --app campfire --static-only
#
# Nothing in this experiment is believable without this script. The whole design
# rests on one claim -- that the two variants differ in where code lives and in
# nothing else -- and that claim is easy to break by accident and impossible to
# spot by eye across 302 moved files.
#
# Four static checks, read straight out of git:
#
#   1. every file's content is byte-identical after applying the move manifest,
#      except the declared wiring files
#   2. no class, module, method or constant is renamed, added or removed
#      anywhere in the tree
#   3. every declared autoload root exists on disk
#   4. Gemfile and Gemfile.lock are untouched, so both variants resolve to the
#      same gems
#
# Check 2 is the one that guarantees the comparison is about path knowledge
# rather than searchability: if the same identifiers exist in the same numbers
# on both sides, an agent that navigates by `grep "def deliver"` finds exactly
# as much either way, and anything it loses is prediction.
#
# Three runtime checks, which need the app image and so run in a container:
#
#   5. `bin/rails zeitwerk:check` passes on both, which is what catches a
#      concerns/ directory that quietly became a namespace
#   6. `bin/rails routes` is identical on both, line for line
#   7. `bin/rails test` is green on both
#
# A scramble that fails any of these has changed the application, not its
# layout, and every number measured against it would be measuring that change.

require "fileutils"
require "json"
require "tmpdir"
require_relative "../../containers/scripts/lib/kit"

BRANCH_PREFIX = "exp/convention"

app_key = nil
static_only = false

args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--app" then app_key = args.shift
  when "--static-only" then static_only = true
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

manifest_path = File.join(EXPERIMENT_DIR, "variants", app_key, "manifest.json")
abort "missing #{manifest_path}; run scramble.rb first" unless File.exist?(manifest_path)
manifest = JSON.parse(File.read(manifest_path))

CONVENTIONAL = manifest["conventional_branch"]
SCRAMBLED = manifest["scrambled_branch"]
MOVES = manifest["moves"]
WIRING = manifest["wiring"]

failures = []
passes = []

def record(list, label, detail = nil)
  list << (detail ? "#{label}\n#{detail}" : label)
end

# --- 1. content ---------------------------------------------------------------
#
# git already hashes every blob, so comparing content across 700 files is a
# comparison of two hash maps rather than 700 file reads.
def tree_blobs(repo, branch)
  Kit.capture("git", "-C", repo, "ls-tree", "-r", branch).lines.to_h do |line|
    meta, path = line.chomp.split("\t", 2)
    [path, meta.split[2]]
  end
end

conventional_blobs = tree_blobs(repo, CONVENTIONAL)
scrambled_blobs = tree_blobs(repo, SCRAMBLED)

expected = conventional_blobs.to_h { |path, sha| [MOVES[path] || path, sha] }

wiring = WIRING.to_h { |w| [w, true] }
mismatched = []
missing = []
(expected.keys - wiring.keys).each do |path|
  actual = scrambled_blobs[path]
  if actual.nil?
    missing << path
  elsif actual != expected[path]
    mismatched << path
  end
end
unexpected = scrambled_blobs.keys - expected.keys - wiring.keys

if mismatched.empty? && missing.empty? && unexpected.empty?
  record(passes, "content: #{expected.size} file(s) identical after applying the manifest")
else
  detail = []
  detail << "  contents changed : #{mismatched.first(10).inspect}" if mismatched.any?
  detail << "  missing          : #{missing.first(10).inspect}" if missing.any?
  detail << "  not in either    : #{unexpected.first(10).inspect}" if unexpected.any?
  record(failures, "content: the scramble edited files it should only have moved", detail.join("\n"))
end

# --- 2. identifiers -----------------------------------------------------------
#
# Counted rather than set-compared: a set would hide a rename that happened to
# collide with an identifier already present elsewhere in the tree.
DEFINITION_PATTERNS = [
  /^\s*(?:class|module)\s+([A-Z][\w:]*)/,
  /^\s*def\s+(?:self\.)?([a-z_][\w?!=]*)/,
  /^\s*([A-Z][A-Z0-9_]{2,})\s*=[^=~]/
].freeze

def identifier_counts(repo, branch)
  counts = Hash.new(0)
  Dir.mktmpdir("llmx-check") do |dir|
    tar = File.join(dir, "tree.tar")
    Kit.sh("git", "-C", repo, "archive", "--format=tar", "-o", tar, branch)
    Kit.sh("tar", "-xf", tar, "-C", dir)
    Dir.glob(File.join(dir, "**", "*.rb")).each do |file|
      File.readlines(file, chomp: true).each do |line|
        DEFINITION_PATTERNS.each do |pattern|
          counts[Regexp.last_match(1)] += 1 if line.match?(pattern) && line =~ pattern
        end
      end
    end
  end
  counts
end

before = identifier_counts(repo, CONVENTIONAL)
after = identifier_counts(repo, SCRAMBLED)

drifted = (before.keys | after.keys).reject { |k| before[k] == after[k] }
if drifted.empty?
  record(passes, "identifiers: #{before.size} distinct name(s), same counts on both variants")
else
  detail = drifted.first(20).map { |k| format("  %-40s conventional=%d scrambled=%d", k, before[k], after[k]) }
  record(failures, "identifiers: #{drifted.size} name(s) differ, so grep is not equally powerful",
         detail.join("\n"))
end

# --- 3. autoload roots --------------------------------------------------------
absent = manifest["autoload_roots"].reject do |rel|
  Kit.capture("git", "-C", repo, "ls-tree", "-d", "--name-only", "#{SCRAMBLED}:#{rel}",
              allow_failure: true).strip != "" ||
    Kit.capture("git", "-C", repo, "ls-tree", "--name-only", "#{SCRAMBLED}", "#{rel}/",
                allow_failure: true).strip != ""
end
if absent.empty?
  record(passes, "autoload roots: all #{manifest['autoload_roots'].size} present in the scrambled tree")
else
  record(failures, "autoload roots: declared but not present", "  #{absent.inspect}")
end

# --- 4. gems ------------------------------------------------------------------
gem_drift = %w[Gemfile Gemfile.lock].reject { |f| conventional_blobs[f] == scrambled_blobs[f] }
if gem_drift.empty?
  record(passes, "gems: Gemfile and Gemfile.lock identical on both variants")
else
  record(failures, "gems: #{gem_drift.inspect} differ, so the variants may not resolve the same gems")
end

puts "\n=== static checks ==="
passes.each { |p| puts "  ok    #{p}" }
failures.each { |f| puts "  FAIL  #{f}" }

if static_only
  puts(failures.empty? ? "\nstatic checks passed" : "\n#{failures.size} static check(s) FAILED")
  exit(failures.empty? ? 0 : 1)
end

unless failures.empty?
  puts "\n#{failures.size} static check(s) FAILED; not spending container time on the runtime checks"
  exit 1
end

# --- runtime ------------------------------------------------------------------
image = "llmx-conv-#{app_key}:latest"
Kit.ensure_system_started!
unless Kit.image_exists?(image)
  abort "image #{image} not found; run build_variant_image.rb --app #{app_key} first"
end

out_dir = Dir.mktmpdir("llmx-check-out")
FileUtils.cp(File.join(__dir__, "check_runtime.rb"), File.join(out_dir, "check_runtime.rb"))

cmd = ["container", "run", "--rm",
       *Kit.run_args(mount_auth: false),
       "--volume", "#{out_dir}:/results",
       "--workdir", "/workspace/app",
       "--env", "LLMX_DB_PREPARE=#{app['db_prepare']}",
       "--env", "LLMX_DATABASE=#{app['database']}",
       image, "bash", "-lc", "exec ruby /results/check_runtime.rb"]

puts "\n=== runtime checks (in #{image}) ==="
ok = system(*cmd)

report_path = File.join(out_dir, "runtime.json")
unless File.exist?(report_path)
  abort "the runtime checks produced no report (container exit #{ok.inspect}); inspect #{out_dir}"
end

report = JSON.parse(File.read(report_path))
report["checks"].each do |check|
  puts format("  %-5s %s", check["ok"] ? "ok" : "FAIL", check["label"])
  puts check["detail"].lines.first(20).map { |l| "        #{l}" }.join unless check["ok"] || check["detail"].to_s.empty?
end

runtime_failed = report["checks"].reject { |c| c["ok"] }
FileUtils.cp(report_path, File.join(EXPERIMENT_DIR, "variants", app_key, "scramble_check.json"))

if runtime_failed.empty?
  puts "\nall checks passed: the two variants differ in layout and nothing else"
  exit 0
end

puts "\n#{runtime_failed.size} runtime check(s) FAILED. Report kept at " \
     "convention-navigation/variants/#{app_key}/scramble_check.json"
exit 1
