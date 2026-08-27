#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs both experiments against one model and records what they measured.
#
#   ruby word-vector-arithmetic/scripts/run.rb                        # glove
#   ruby word-vector-arithmetic/scripts/run.rb --model gpt2
#   ruby word-vector-arithmetic/scripts/run.rb --model gpt2 --slice   # no download
#
# THIS SCRIPT MEASURES, report.rb DECIDES WHAT IT MEANS. Everything here is a
# raw observation: which word came first, what rank the expected answer got,
# what the two dot products were. No accuracy, no average, no verdict. That
# split is what lets a claim be rechecked without rerunning a scan.
#
# EVERY ANALOGY IS RANKED TWICE, AND ON GPT-2 THREE TIMES. Once with a, b and c
# still in the running and once with them excluded -- gensim's most_similar
# drops them silently, find_nearest_words in 3b1b/videos does not, and which one
# you use decides whether the famous example is a hit. GPT-2 adds a third:
# ranked against word-like tokens only, because its vocabulary is full of
# fragments that no GloVe ranking could ever have returned. Recording all of
# them beats choosing the flattering one.
#
# THE SAME words.yml FEEDS BOTH MODELS. Comparability is the entire reason the
# GPT-2 run exists, so nothing about the item list may differ between them.
#
# --slice IS A REPRODUCTION CHECK, NOT A SECOND EXPERIMENT. It reruns the
# direction test off the committed slice and demands numbers identical to the
# committed results. It is how a clean clone verifies a result without the
# download.

require "digest"
require "json"
require_relative "lib/models"
require_relative "lib/vectors"
require_relative "../../containers/scripts/lib/kit"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
WORDS = File.join(EXPERIMENT_DIR, "words.yml")
RESULTS = File.join(EXPERIMENT_DIR, "results")
METRICS = %i[euclidean cosine].freeze

def option(name, default)
  index = ARGV.index("--#{name}")
  index ? ARGV.fetch(index + 1) : default
end

def token_forms(table, words)
  return nil unless table.respond_to?(:resolve)

  words.to_h { |word| [word, table.resolve(word)&.last] }
end

def analogy_rows(table, analogies, pool, skipped)
  analogies.map do |quad|
    a, b, c, d = quad.values_at("a", "b", "c", "d")
    missing = [a, b, c, d].reject { |w| table.include?(w) }
    unless missing.empty?
      warn "  skipped #{a}:#{b}::#{c}:#{d} -- not in this model: #{missing.join(", ")}"
      skipped.concat(missing)
      next
    end

    target = Vectors.add(Vectors.sub(table.fetch(b), table.fetch(a)), table.fetch(c))
    row = { "relation" => quad["relation"], "a" => a, "b" => b, "c" => c, "expected" => d }
    row["group"] = quad["group"] if quad["group"]
    forms = token_forms(table, [a, b, c, d])
    row["tokens"] = forms if forms

    METRICS.each do |metric|
      scores = table.scores(target, metric: metric)
      with_inputs = table.ranking_from(scores)
      without_inputs = table.ranking_from(scores, exclude: [a, b, c])
      pooled = pool && table.ranking_from(scores, exclude: [a, b, c], restrict: pool)
      row[metric.to_s] = {
        "top1_with_inputs" => with_inputs.top(1).first.first,
        "rank_with_inputs" => with_inputs.rank_of(d),
        "top1" => without_inputs.top(1).first.first,
        "rank" => without_inputs.rank_of(d),
        "top5" => without_inputs.top(5).map(&:first),
        "top1_word_like" => pooled&.top(1)&.first&.first,
        "rank_word_like" => pooled&.rank_of(d)
      }
    end

    warn format("  %-11s %s - %s + %s -> %s (rank of %s: %s, %s with inputs)",
                quad["relation"], b, a, c,
                row["euclidean"]["top1"].inspect, d,
                row["euclidean"]["rank"], row["euclidean"]["rank_with_inputs"])
    row
  end.compact
end

def direction_of(table, pair)
  Vectors.sub(table.fetch(pair["plural"]), table.fetch(pair["singular"]))
end

def direction_rows(table, config, skipped)
  directions = {
    "seed" => direction_of(table, config["direction_seed"]),
    "averaged" => Vectors.mean(config["direction_training"].map { |p| direction_of(table, p) })
  }

  config["direction_test"].map do |pair|
    singular, plural = pair.values_at("singular", "plural")
    missing = [singular, plural].reject { |w| table.include?(w) }
    unless missing.empty?
      warn "  skipped #{singular}/#{plural} -- not in this model: #{missing.join(", ")}"
      skipped.concat(missing)
      next
    end

    row = { "singular" => singular, "plural" => plural, "form" => pair["form"] }
    forms = token_forms(table, [singular, plural])
    row["tokens"] = forms if forms

    directions.each do |name, direction|
      direction_norm = Vectors.norm(direction)
      %w[dot cosine].each do |metric|
        scores = [singular, plural].to_h do |word|
          vector = table.fetch(word)
          raw = Vectors.dot(vector, direction)
          value = metric == "dot" ? raw : raw / (Vectors.norm(vector) * direction_norm)
          [word == singular ? "singular" : "plural", value]
        end
        scores["separates"] = scores["plural"] > scores["singular"]
        row["#{name}_#{metric}"] = scores
      end
    end
    row
  end.compact
end

def provenance(model, table, slice_mode, pool, skipped)
  sources = Models.required(model, slice: slice_mode).to_h do |path|
    [File.basename(path), Digest::SHA256.file(path).hexdigest]
  end
  {
    "model" => model,
    "read_from" => slice_mode ? "committed slice" : "data/",
    "sources" => sources,
    "vocabulary" => table.size,
    "dimensions" => table.dims,
    "candidate_pool" => pool ? pool.size : nil,
    # Recorded, never inferred: a word absent from this model is why an item
    # count differs between models, and the report has to say so out loud.
    "words_without_a_vector" => skipped.uniq.sort,
    "words_yml_sha256" => Digest::SHA256.file(WORDS).hexdigest,
    "ruby" => RUBY_VERSION
  }
end

model = option("model", "glove")
abort "unknown model #{model.inspect}; expected #{Models::ALL.join(" or ")}" unless Models::ALL.include?(model)

slice_mode = ARGV.include?("--slice")
config = Kit::TinyYAML.load_file(WORDS)

missing = Models.required(model, slice: slice_mode).reject { |path| File.exist?(path) }
unless missing.empty?
  hint = model == "gpt2" ? "scripts/fetch_gpt2.rb" : "scripts/fetch.rb"
  abort "missing #{missing.map { |p| File.basename(p) }.join(", ")}; run #{hint} first"
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
warn "loading #{model}#{slice_mode ? " (committed slice)" : ""}"
table = Models.load(model, slice: slice_mode)
warn format("  %d entries, %d dimensions, %.1fs", table.size, table.dims,
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)

pool = slice_mode ? nil : Models.candidate_pool(model, table)
warn "  candidate pool: #{pool.size} word-like tokens of #{table.size}" if pool

warn "plural direction: #{config["direction_test"].length} held-out pairs"
direction_skipped = []
direction_pairs = direction_rows(table, config, direction_skipped)
direction = {
  "provenance" => provenance(model, table, slice_mode, pool, direction_skipped),
  "seed" => config["direction_seed"],
  "training" => config["direction_training"],
  "pairs" => direction_pairs
}

direction_path = File.join(RESULTS, "direction-#{model}.json")

if slice_mode
  abort "nothing committed at #{direction_path} to check against" unless File.exist?(direction_path)

  committed = JSON.parse(File.read(direction_path))
  if committed["pairs"] == direction["pairs"]
    warn "slice reproduces #{File.basename(direction_path)} exactly (#{direction["pairs"].length} pairs)"
    exit 0
  end

  differing = committed["pairs"].zip(direction["pairs"]).reject { |x, y| x == y }
  warn "MISMATCH on #{differing.length} pairs; first: #{differing.first.inspect}"
  exit 1
end

File.write(direction_path, "#{JSON.pretty_generate(direction)}\n")

warn "analogies: #{config["analogies"].length} quadruples x #{METRICS.length} metrics"
analogy_skipped = []
analogy_analogies = analogy_rows(table, config["analogies"], pool, analogy_skipped)
analogy = {
  "provenance" => provenance(model, table, slice_mode, pool, analogy_skipped),
  "analogies" => analogy_analogies
}
File.write(File.join(RESULTS, "analogy-#{model}.json"), "#{JSON.pretty_generate(analogy)}\n")

warn format("done in %.1fs", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
