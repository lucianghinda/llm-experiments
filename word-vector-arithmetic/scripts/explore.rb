#!/usr/bin/env ruby
# frozen_string_literal: true

# Asks one model one question and prints the whole ranking.
#
#   ruby word-vector-arithmetic/scripts/explore.rb                        # prompt
#   ruby word-vector-arithmetic/scripts/explore.rb "collect - map + length = size"
#   ruby word-vector-arithmetic/scripts/explore.rb --model gpt2 "woman - man + king"
#   ruby word-vector-arithmetic/scripts/explore.rb --slice "cats - cat + dog"
#
# WHY THIS EXISTS. results/*.json keeps the top 5 and the rank of the one word
# words.yml nominated. The scan computed a score for all 400,000, and everything
# else was thrown away. This prints the part that was thrown away, which is where
# the answers to "why did it say that?" live: the Bitcoin sitting next to hash,
# the snake sitting next to python, the four spellings of length that crowd out
# a correct answer.
#
# IT MEASURES NOTHING AND DECIDES NOTHING. No committed result depends on this
# file, and it writes nothing. run.rb is the experiment; this is a way to look
# at a model. Keeping them apart is what stops an interesting session from
# quietly becoming a reported number.
#
# THE LIST EXCLUDES INPUT WORDS, AS run.rb DOES, and the line under it says what
# happens when they are kept. That gap is the experiment's first finding, so the
# tool shows it on every query rather than making you ask twice.
#
# GPT-2 PRINTS ITS TOKENS, NOT YOUR WORDS. " Rome" and "rome" are different rows
# and picking the wrong one once cost four orders of magnitude, so every answer
# says which row it actually used.

require_relative "lib/models"
require_relative "lib/vectors"

begin
  require "reline"
  def read_line(prompt) = Reline.readline(prompt, true)
rescue LoadError
  def read_line(prompt)
    print prompt
    $stdin.gets&.chomp
  end
end

RULE = ("-" * 72).freeze

def option(name, default)
  index = ARGV.index("--#{name}")
  return default unless index

  value = ARGV.fetch(index + 1)
  ARGV.slice!(index, 2)
  value
end

def flag(name)
  ARGV.delete("--#{name}") ? true : false
end

def commas(number) = number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse

# "collect - map + length = size" becomes the terms and the word to look up.
# Operators must be surrounded by spaces so that hyphenated entries like
# "client-side" stay one word.
def parse(expression)
  body, expected = expression.split(/\s+(?:=|->)\s+/, 2)
  parts = body.split(/\s+/).reject(&:empty?)
  raise ArgumentError, "nothing to compute" if parts.empty?

  terms = []
  sign = 1
  want_word = true
  parts.each do |part|
    if want_word
      raise ArgumentError, "expected a word, found #{part.inspect}" if %w[+ -].include?(part)

      terms << [part.downcase, sign]
      want_word = false
    else
      case part
      when "+" then sign = 1
      when "-" then sign = -1
      else raise ArgumentError, "expected + or - between words, found #{part.inspect}"
      end
      want_word = true
    end
  end
  raise ArgumentError, "expression ends with an operator" if want_word

  [terms, expected&.strip&.downcase]
end

def target_for(table, terms)
  terms.reduce(Array.new(table.dims, 0.0)) do |total, (word, sign)|
    vector = table[word] or raise KeyError, word

    sign.positive? ? Vectors.add(total, vector) : Vectors.sub(total, vector)
  end
end

def render(model, table, pool, terms, expected, metric, count)
  words = terms.map(&:first)
  shown = ->(entry) { model == "gpt2" ? entry.inspect : entry }

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  target = target_for(table, terms)
  scores = table.scores(target, metric: metric)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

  # A single word means "what is near this?", so the word itself is dropped for
  # the same reason the inputs are: it is always its own nearest neighbour.
  ranked = table.ranking_from(scores, exclude: words, restrict: pool)
  kept = table.ranking_from(scores, restrict: pool)

  expression = terms.map.with_index { |(word, sign), i|
    i.zero? ? (sign.positive? ? word : "-#{word}") : "#{sign.positive? ? "+" : "-"} #{word}"
  }.join(" ")

  puts RULE
  puts format("%s | %s | %s | %s entries%s | %.1fs",
              model, expression, metric, commas(pool ? pool.size : table.size),
              pool ? " (word-like only)" : "", elapsed)
  if model == "gpt2"
    used = words.to_h { |word| [word, table.resolve(word)&.last] }
    puts "tokens used: #{used.map { |word, token| "#{word} #{shown.call(token)}" }.join("  ")}"
  end
  puts RULE

  expected_rank = expected && ranked.rank_of(expected)
  ranked.top(count).each_with_index do |(entry, score), i|
    marker = expected && expected_rank == i + 1 ? "  <-- expected" : ""
    puts format("%5d  %-28s %8.3f%s", i + 1, shown.call(entry), score, marker)
  end

  if expected && expected_rank && expected_rank > count
    puts format("%5s  %s", "...", "")
    puts format("%5d  %-28s %8.3f  <-- expected",
                expected_rank, shown.call(table.word_at(table.index_of(expected))),
                scores[table.index_of(expected)])
  elsif expected && expected_rank.nil?
    puts "       #{expected.inspect} has no vector in #{model}, so it has no rank."
  end

  first_kept = kept.top(1).first
  note = words.include?(first_kept.first.strip.downcase) ? " -- an input word" : ""
  puts RULE
  puts format("inputs kept: %s comes first%s%s", shown.call(first_kept.first), note,
              expected_rank ? format("; %s moves to %d", expected, kept.rank_of(expected)) : "")
  puts "input ranks:  #{words.map { |w| "#{w} #{commas(kept.rank_of(w) || 0)}" }.join("  ")}"
  puts
end

def ask(models, tables, pools, expression, metric, count, slice)
  terms, expected = parse(expression)
  models.each do |model|
    render(model, tables[model], pools[model], terms, expected, metric, count)
  rescue KeyError => e
    puts "#{model}: no vector for #{e.message.inspect}#{" (the slice holds only words.yml's words)" if slice}"
    puts
  end
rescue ArgumentError => e
  puts "cannot read that: #{e.message}"
  puts "expected something like: collect - map + length = size"
  puts
end

HELP = <<~TEXT
  Type an expression. Operators need spaces around them.

    woman - man + king            rank every word against that point
    woman - man + king = queen    and say where queen landed
    hash                          just the nearest words to hash

  Commands:
    :model glove | gpt2 | both    which model answers
    :metric euclidean | cosine    how distance is measured
    :top 30                       how many rows to print
    :help                         this
    :quit                         or Ctrl-D

TEXT

slice = flag("slice")
word_like = flag("word-like")
metric = option("metric", "euclidean").to_sym
count = option("top", "15").to_i
wanted = option("model", "both")

unless %i[euclidean cosine].include?(metric)
  abort "unknown metric #{metric.inspect}; expected euclidean or cosine"
end

models = wanted == "both" ? Models::ALL.dup : [wanted]
unknown = models - Models::ALL
abort "unknown model #{unknown.first.inspect}; expected #{Models::ALL.join(", ")} or both" unless unknown.empty?

models.select! do |model|
  next true if Models.available?(model, slice: slice)

  hint = model == "gpt2" ? "scripts/fetch_gpt2.rb" : "scripts/fetch.rb"
  warn "skipping #{model}: no #{slice ? "slice" : "table"} on disk; run #{hint}"
  false
end
abort "no model available" if models.empty?

tables = {}
pools = {}
models.each do |model|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  tables[model] = Models.load(model, slice: slice)
  # The word-like pool is GPT-2's alternative candidate set, off unless asked
  # for, because hiding rows changes the question being answered.
  pools[model] = word_like ? Models.candidate_pool(model, tables[model]) : nil
  warn format("loaded %s: %s entries, %d dimensions, %.1fs", model,
              commas(tables[model].size), tables[model].dims,
              Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
end
warn ""

unless ARGV.empty?
  ask(models, tables, pools, ARGV.join(" "), metric, count, slice)
  exit 0
end

print HELP
loop do
  line = read_line("> ")
  break if line.nil?

  line = line.strip
  next if line.empty?

  case line
  when ":quit", ":q", ":exit" then break
  when ":help", ":h" then print HELP
  when /\A:model\s+(\S+)\z/
    choice = Regexp.last_match(1)
    picked = choice == "both" ? Models::ALL & tables.keys : [choice] & tables.keys
    if picked.empty?
      puts "#{choice} is not loaded; started with #{tables.keys.join(", ")}"
    else
      models = picked
      puts "answering with #{models.join(" and ")}"
    end
  when /\A:metric\s+(\S+)\z/
    choice = Regexp.last_match(1).to_sym
    if %i[euclidean cosine].include?(choice)
      metric = choice
      puts "measuring with #{metric}"
    else
      puts "unknown metric #{choice}; expected euclidean or cosine"
    end
  when /\A:top\s+(\d+)\z/
    count = Regexp.last_match(1).to_i
    puts "printing #{count} rows"
  when /\A:/ then puts "unknown command #{line}; try :help"
  else ask(models, tables, pools, line, metric, count, slice)
  end
end
