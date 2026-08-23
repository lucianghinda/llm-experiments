#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates the task prompts and publishes them.
#
#   ruby convention-navigation/scripts/render_prompts.rb
#   ruby convention-navigation/scripts/render_prompts.rb --check
#
# There is ONE prompt per task, not one per condition. The prompt is the
# constant and the layout is the variable; rendering it per condition would
# reintroduce the thing this experiment removes.
#
# So what is there to validate? The rule that a prompt may not hand over a
# location. It is easy to state and easy to break by accident -- an early draft
# of one prompt used "12" as the example format for an answer whose correct
# value is 12 -- so it is checked mechanically rather than by reading.
#
# THE GREP COUPON RULE
#
# A prompt word is a coupon when grepping the codebase for it returns a handful
# of files AND ONE OF THEM IS A FILE THIS TASK'S ANSWER LIVES IN. Such a word
# does not describe the task, it points at the answer, and it points equally
# well in both variants, which silently shrinks the effect toward zero and makes
# the experiment look like it disproved its own hypothesis.
#
# Both halves of that rule are load-bearing, and the first draft had only the
# first half. Counting files alone flagged "exactly", "written" and "able" --
# ordinary English that happens to appear once somewhere in a comment. Grepping
# for those leads nowhere near the answer, so they are not coupons and refusing
# them only makes the prompts stilted.
#
# Tying it to the targets also catches a leak that counting would have found by
# luck and that reading missed entirely: campfire's Room model carries a comment
# containing the word "conversation", so a prompt describing the rule in those
# words greps straight to the file the agent was supposed to go looking for.
#
# Ordinary domain words are fine and are supposed to be there. "room" occurs in
# a hundred files, so it locates nothing; a real person would say it; and an
# agent has to search or predict either way.
#
# Words that occur in NO file are also fine. "topic" names something the task is
# asking for that does not exist yet, which is the opposite of a coupon.

require "fileutils"
require_relative "../../containers/scripts/lib/kit"

# 1..COUPON_MAX files means the word pinpoints. Three is deliberately generous:
# a word matching four files is already a search rather than a lookup.
COUPON_MAX = 3
MIN_WORD = 4

check_only = ARGV.include?("--check")

EXPERIMENT_DIR = File.expand_path("..", __dir__)
apps = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "apps.yml"))["apps"]
tasks = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "tasks.yml"))["tasks"]
scrambles = Kit::TinyYAML.load_file(File.join(EXPERIMENT_DIR, "scramble.yml"))["scrambles"]

BRANCHES = { "conventional" => "exp/convention/conventional",
             "scrambled" => "exp/convention/scrambled" }.freeze

def repo_for(app)
  var = "LLMX_APP_#{app['key'].upcase}"
  path = ENV[var]
  abort "#{var} is not set. See convention-navigation/apps.local.example" if path.nil? || path.empty?

  path
end

# Directory names that belong to one layout and not the other. A prompt naming
# one has told the agent where to look, which is the whole variable.
#
# Segments common to both sides are not forbidden, because they cannot inform:
# `test` and `db` are roots in either arrangement, so a task that says "put it
# where tests belong" gives nothing away. Forbidding them would only make a
# test-writing task impossible to phrase.
def layout_words(spec)
  rules = Array(spec["roots"]) + Array(spec["tests"])
  from = rules.flat_map { |r| r["from"].to_s.split("/") }.uniq
  to = rules.flat_map { |r| r["to"].to_s.split("/") }.uniq
  ((from - to) | (to - from)).reject(&:empty?)
end

# Which files in this branch contain the word, case-insensitively. Agents grep
# without regard for case, so asking with regard for it would understate how
# well a word locates.
def matching_files(repo, branch, word)
  Kit.capture("git", "-C", repo, "grep", "-l", "-i", "-w", "-F", word, branch,
              allow_failure: true)
     .lines.map { |l| l.chomp.sub("#{branch}:", "") }
end

violations = []
rendered = []

apps.each do |app|
  app_tasks = tasks.select { |t| t["app"] == app["key"] }
  next if app_tasks.empty?

  repo = repo_for(app)
  spec = scrambles[app["key"]] or abort "scramble.yml has no entry for #{app['key']}"
  forbidden_dirs = layout_words(spec)

  # Asked once per word for the whole app rather than once per prompt: the same
  # words recur across tasks and each question is a subprocess.
  hits = Hash.new do |h, key|
    variant, word = key
    h[key] = matching_files(repo, BRANCHES[variant], word)
  end

  app_tasks.each do |task|
    source = File.join(EXPERIMENT_DIR, "prompts-src", app["key"], task["prompt"])
    abort "missing prompt #{source}" unless File.exist?(source)

    text = File.read(source)
    problems = []

    # Anything shaped like a path. The format lines the prompts use to show the
    # agent how to answer are the one exception: "path/to/file.rb:LINE" is a
    # template, not a location, and it names no directory in either variant.
    text.scan(%r{[\w.-]+/[\w./-]+}).uniq.each do |candidate|
      next if candidate.start_with?("path/to/")

      problems << "looks like a path: #{candidate.inspect}"
    end

    words = text.scan(/[A-Za-z_][A-Za-z0-9_]{#{MIN_WORD - 1},}/).uniq

    words.each do |word|
      problems << "names a layout directory: #{word.inspect}" if forbidden_dirs.include?(word)

      BRANCHES.each_key do |variant|
        targets = Array(task["targets_#{variant}"])
        files = hits[[variant, word]]
        next unless files.size.between?(1, COUPON_MAX)

        led_to = files & targets
        next if led_to.empty?

        problems << "grep coupon: #{word.inspect} occurs in #{files.size} file(s) on " \
                    "#{variant} and one of them is #{led_to.join(', ')}"
      end
    end

    if problems.empty?
      rendered << { task: task, text: text }
    else
      violations << { task: task["id"], problems: problems }
    end
  end
end

if violations.any?
  warn "REFUSING to render. #{violations.size} prompt(s) hand over a location:\n"
  violations.each do |v|
    warn "  #{v[:task]}"
    v[:problems].uniq.each { |p| warn "    - #{p}" }
  end
  warn "\nRephrase in behaviour, or widen the wording until it stops pointing at one file."
  exit 1
end

puts "#{rendered.size} prompt(s) validated: no paths, no layout directories, no grep coupons"
exit 0 if check_only

out_dir = File.join(EXPERIMENT_DIR, "prompts")
FileUtils.rm_rf(out_dir)
rendered.each do |r|
  target = File.join(out_dir, r[:task]["app"], "#{r[:task]['id']}.txt")
  FileUtils.mkdir_p(File.dirname(target))
  File.write(target, r[:text])
end

File.write(File.join(EXPERIMENT_DIR, "PROMPTS.md"), <<~MD)
  # Prompts

  Generated by `scripts/render_prompts.rb`. Do not edit: edit `prompts-src/`
  and re-render, so the published text and the text the runner sends cannot
  drift apart.

  One prompt per task. Every condition gets the same words, because the layout
  is the variable and the wording is not.

  Each has been checked mechanically for three things: no file path, no name of
  a directory belonging to one layout and not the other, and no word that occurs
  in #{COUPON_MAX} or fewer files **when one of those files is where this task's
  answer lives**.

  That last one is the rule that matters, and both halves of it are
  load-bearing. A word narrow enough to grep straight to the answer helps both
  conditions equally and hides the effect being measured. A word that is merely
  rare -- "exactly", "written" -- points nowhere near the answer and is fine.
  Tying the rule to each task's targets is what separates them, and it caught a
  leak that reading the prompts had missed: campfire's Room model carries a
  comment containing the word "conversation", so describing the rule in that
  word grepped straight to the file the agent was supposed to go find.

  #{rendered.map do |r|
      task = r[:task]
      <<~ENTRY
        ## #{task['id']}

        - app: #{task['app']}
        - family: #{task['family']}
        - success decided by: `checks/#{task['app']}/#{task['check']}`

        ```
        #{r[:text].chomp}
        ```
      ENTRY
    end.join("\n")}
MD

puts "wrote prompts/ and PROMPTS.md"
