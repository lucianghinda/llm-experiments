#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders every prompt from bugs.yml, and writes PROMPTS.md from the same
# template so the documentation cannot drift from what was actually sent.
#
# The three conditions differ only in the hint block:
#
#   none   one sentence of domain language, no path and no line
#   bare   the paths, written plainly
#   at     the same paths, each prefixed with @
#
# bare and at are checked byte for byte: removing the @ prefixes from the at
# prompt must reproduce the bare prompt exactly. If it does not, the render
# fails rather than quietly measuring two differences at once.
#
#   ruby at-file-mentions/scripts/render_prompts.rb
#   ruby at-file-mentions/scripts/render_prompts.rb --check   # verify, write nothing

require "fileutils"
require_relative "../../containers/scripts/lib/kit"

BRANCH_PREFIX = "exp/path-hints"
WORKTREE_ROOT = ENV.fetch("LLMX_PLANT_ROOT", "/tmp/llmx/plant")
# Five conditions, in two families.
#
# The line-suffixed pair came first and turned out to be inert on both sides:
# `@file.rb:22` is not a path that resolves, so the mention stays literal text
# and the @ buys nothing. That is a real answer about the form people write
# after reading a stack trace, so it is kept rather than deleted.
#
# The bare-path pair is what actually exercises the feature. `@file.rb` resolves
# and the file arrives in the first request - about 1,600 tokens for a 2.9 KB
# file. See scripts/probe_mention.rb, which is the positive control that proves
# the manipulation does something before any trial is spent on it.
CONDITIONS = %w[none bare at bare_noline at_noline].freeze

# Which conditions must be byte-identical apart from @ prefixes.
AT_PAIRS = { "at" => "bare", "at_noline" => "bare_noline" }.freeze

check_only = ARGV.include?("--check")

EXPERIMENT_DIR = File.expand_path("..", __dir__)
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
bugs = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "bugs.yml"))["bugs"]

planted_path = File.join(EXPERIMENT_DIR, "planted.yml")
PLANTED = File.exist?(planted_path) ? (Kit::TinyYAML.load_file(planted_path)["planted"] || []) : []
warn "[kit] no planted.yml yet; test line numbers are guessed from the fix diff" if PLANTED.empty?

# The task anchor is the failing test, and it is named in all three conditions.
# Without it the agent has to run a whole Rails suite before it can even see the
# problem, and that runtime would swamp the cost difference being measured.
# What the conditions vary is whether the DEFECT location is handed over.
TEMPLATE = <<~PROMPT
  A test in this Rails application fails:

      bin/rails test %<test_file>s

  Find the defect in the application code and fix it so that test passes.

  Do not edit anything under test/. Check your work with that same command and nothing else.

  %<hint>s
PROMPT

def app_for(apps, key)
  apps.find { |a| a["key"] == key } or abort "bugs.yml references unknown app #{key}"
end

def worktree_for(app_key)
  dir = File.join(WORKTREE_ROOT, app_key)
  abort "no worktree at #{dir}; run plant.rb first" unless Dir.exist?(dir)
  dir
end

def bug_branch(bug)
  "#{BRANCH_PREFIX}/bug-#{bug['id']}-#{bug['slug']}"
end

# Where the defect now lives: the first line the planting commit rewrote.
def defect_line(worktree, bug)
  branch = bug_branch(bug)
  diff = Kit.capture("git", "-C", worktree, "diff", "-U0",
                     "#{BRANCH_PREFIX}/base", branch, "--", bug["impl_files"].first)
  m = diff[/^@@ -\d+(?:,\d+)? \+(\d+)/, 1]
  m ? m.to_i : 1
end

# Where the regression test lives.
#
# plant_check.rb runs the suite and records the line of the test that actually
# fails; that is the honest answer and it is used whenever it is available. The
# fallback below guesses from the fix commit's diff, which can point at the
# wrong test: a fix that replaces one test with two leaves the first one passing.
def test_line(worktree, bug, planted)
  recorded = planted.find { |p| p["id"] == bug["id"] }
  return recorded["test_line"] if recorded && recorded["test_line"].to_i.positive?

  test_line_from_diff(worktree, bug)
end

def test_line_from_diff(worktree, bug)
  branch = bug_branch(bug)
  added = Kit.capture("git", "-C", worktree, "show", bug["fix_sha"], "--", bug["test_file"])
             .lines
             .select { |l| l.start_with?("+") }
             .map { |l| l[1..].to_s }

  names = added.filter_map do |line|
    line[/\A\s*test\s+["'](.+?)["']\s+do/, 1] || line[/\A\s*def\s+(test_\w+)/, 1]
  end

  body = Kit.capture("git", "-C", worktree, "show", "#{branch}:#{bug['test_file']}").lines
  names.each do |name|
    idx = body.index { |l| l.include?(name) }
    return idx + 1 if idx
  end
  1
end

def hint_block(condition, bug, lines)
  case condition
  when "none"
    bug["domain_hint"]
  when "bare", "at", "bare_noline", "at_noline"
    prefix = condition.start_with?("at") ? "@" : ""
    suffix = condition.end_with?("_noline") ? "" : ":LINE"
    entries = bug["hint_paths"].map do |p|
      "#{prefix}#{p}#{suffix.sub('LINE', lines.fetch(p).to_s)}"
    end
    (["Relevant files:"] + entries).join("\n")
  end
end

renders = []

bugs.each do |bug|
  app = app_for(apps, bug["app"])
  worktree = worktree_for(app["key"])

  lines = {}
  lines[bug["test_file"]] = test_line(worktree, bug, PLANTED)
  bug["impl_files"].each { |f| lines[f] = defect_line(worktree, bug) }

  missing = bug["hint_paths"].reject { |p| lines.key?(p) }
  abort "#{bug['id']}: hint_paths mentions #{missing.inspect} which is neither the test nor an impl file" if missing.any?

  texts = CONDITIONS.to_h do |condition|
    [condition, format(TEMPLATE, test_file: bug["test_file"], hint: hint_block(condition, bug, lines))]
  end

  # The @ prefix must be the only difference within each pair.
  AT_PAIRS.each do |at_cond, bare_cond|
    stripped = texts[at_cond].gsub(/^@/, "")
    next if stripped == texts[bare_cond]

    abort "#{bug['id']}: #{at_cond} and #{bare_cond} differ by more than the @ prefix"
  end

  # And the noline pair must differ from the line pair only by the suffix, so a
  # comparison across families is attributable to the line number and nothing else.
  %w[bare at].each do |base|
    with_lines = texts[base].gsub(/(\.rb):\d+$/, '\1')
    next if with_lines == texts["#{base}_noline"]

    abort "#{bug['id']}: #{base}_noline differs from #{base} by more than the :line suffix"
  end

  # cond-none must not leak a path or a defect-file basename.
  none = texts["none"]
  leaked = ([bug["test_file"]] + bug["impl_files"]).flat_map do |path|
    [path, File.basename(path, ".rb")] + File.basename(path, ".rb").split("_")
  end.uniq.select { |token| token.length > 3 && none.downcase.include?(token.downcase) }
  # The test file is named in the shared template on purpose; only the hint is checked.
  hint_leak = leaked.select { |t| bug["domain_hint"].downcase.include?(t.downcase) }
  abort "#{bug['id']}: domain_hint leaks #{hint_leak.inspect}" if hint_leak.any?

  renders << { bug: bug, app: app, lines: lines, texts: texts }
end

if check_only
  puts "checked #{renders.size} bug(s): at differs from bare only by @, no domain_hint leaks a filename"
  exit 0
end

prompts_root = File.join(EXPERIMENT_DIR, "prompts")
FileUtils.rm_rf(prompts_root)

renders.each do |r|
  dir = File.join(prompts_root, r[:app]["key"], r[:bug]["id"])
  FileUtils.mkdir_p(dir)
  r[:texts].each do |condition, text|
    File.write(File.join(dir, "#{condition}.txt"), text)
  end
end

doc = +<<~MD
  # Prompts

  Generated by `scripts/render_prompts.rb` from `bugs.yml`, so this file and the
  prompts under `prompts/` cannot disagree. Do not edit either by hand.

  ## The template

  Every prompt is this template with one hint block substituted:

  ```
  #{format(TEMPLATE, test_file: '<TEST FILE>', hint: '<HINT BLOCK>').strip}
  ```

  The failing test is named in **all three** conditions. It is the task anchor:
  without it the agent has to run a whole Rails suite before it can see the
  problem, and that runtime would swamp the cost difference being measured. What
  the conditions vary is whether the **defect location** is handed over, and how
  it is written.

  ## The three hint blocks

  | Condition | Hint block |
  |---|---|
  | `none` | one sentence of domain language: no path, no filename, no line |
  | `bare` | `Relevant files:` then `path:line`, one per line |
  | `at` | the same list with `@` before each path |

  `bare` and `at` are verified byte for byte at render time: stripping the `@`
  prefixes from `at` must reproduce `bare` exactly, so the syntax is the only
  thing that changes between them.

  ## Rendered prompts

MD

renders.each do |r|
  doc << "### #{r[:bug]['id']} — #{r[:app]['key']}\n\n"
  doc << "Planted from `#{r[:bug]['fix_sha']}`. Defect in `#{r[:bug]['impl_files'].join('`, `')}`.\n\n"
  CONDITIONS.each do |condition|
    doc << "<details><summary><code>#{condition}</code></summary>\n\n```\n#{r[:texts][condition].strip}\n```\n\n</details>\n\n"
  end
end

File.write(File.join(EXPERIMENT_DIR, "PROMPTS.md"), doc)

renders.each do |r|
  puts format("  %-22s test:%d defect:%d", r[:bug]["id"],
              r[:lines][r[:bug]["test_file"]], r[:lines][r[:bug]["impl_files"].first])
end
puts "\nwrote #{renders.size * CONDITIONS.size} prompts and PROMPTS.md"
