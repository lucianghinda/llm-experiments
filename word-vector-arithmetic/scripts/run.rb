#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs both experiments and records what they measured.
#
#   ruby word-vector-arithmetic/scripts/run.rb          # both; needs data/
#   ruby word-vector-arithmetic/scripts/run.rb --slice  # direction test only, off vectors-slice.txt
#
# THIS SCRIPT MEASURES, report.rb DECIDES WHAT IT MEANS. Everything here is a
# raw observation: which word came first, what rank the expected answer got,
# what the two dot products were. No accuracy, no average, no verdict. That
# split is what lets a claim be rechecked without rerunning a scan.
#
# EVERY ANALOGY IS RANKED TWICE. Once with a, b and c still in the running and
# once with them excluded. gensim's most_similar drops them silently, the
# find_nearest_words helper in 3b1b/videos does not, and which of the two you
# use decides whether "king - man + woman = queen" is a hit or a miss. Recording
# both makes that visible instead of arguing about it.
#
# --slice IS A REPRODUCTION CHECK, NOT A SECOND EXPERIMENT. It reruns the
# direction test off the committed 49KB slice and demands numbers identical to
# results/direction.json. It is how a clean clone verifies the committed result
# without the 163MB download.

require "digest"
require "json"
require_relative "lib/vectors"
require_relative "../../containers/scripts/lib/kit"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
TABLE = File.join(EXPERIMENT_DIR, "data", "glove.6B.50d.txt")
CHECKSUM = File.join(EXPERIMENT_DIR, "data", "CHECKSUM")
SLICE = File.join(EXPERIMENT_DIR, "vectors-slice.txt")
WORDS = File.join(EXPERIMENT_DIR, "words.yml")
RESULTS = File.join(EXPERIMENT_DIR, "results")
METRICS = %i[euclidean cosine].freeze

def analogy_rows(table, analogies)
  analogies.map do |quad|
    a, b, c, d = quad.values_at("a", "b", "c", "d")
    missing = [a, b, c, d].reject { |w| table.include?(w) }
    unless missing.empty?
      warn "  skipped #{a}:#{b}::#{c}:#{d} -- not in table: #{missing.join(", ")}"
      next
    end

    target = Vectors.add(Vectors.sub(table.fetch(b), table.fetch(a)), table.fetch(c))
    row = { "relation" => quad["relation"], "a" => a, "b" => b, "c" => c, "expected" => d }

    METRICS.each do |metric|
      scores = table.scores(target, metric: metric)
      with_inputs = table.ranking_from(scores)
      without_inputs = table.ranking_from(scores, exclude: [a, b, c])
      row[metric.to_s] = {
        "top1_with_inputs" => with_inputs.top(1).first.first,
        "rank_with_inputs" => with_inputs.rank_of(d),
        "top1" => without_inputs.top(1).first.first,
        "rank" => without_inputs.rank_of(d),
        "top5" => without_inputs.top(5).map(&:first)
      }
    end

    warn format("  %-9s %s - %s + %s -> euclidean %s (rank of %s: %d, %d with inputs)",
                quad["relation"], b, a, c,
                row["euclidean"]["top1"], d,
                row["euclidean"]["rank"], row["euclidean"]["rank_with_inputs"])
    row
  end.compact
end

def direction_of(table, pair)
  Vectors.sub(table.fetch(pair["plural"]), table.fetch(pair["singular"]))
end

def direction_rows(table, config)
  directions = {
    "seed" => direction_of(table, config["direction_seed"]),
    "averaged" => Vectors.mean(config["direction_training"].map { |p| direction_of(table, p) })
  }

  config["direction_test"].map do |pair|
    singular, plural = pair.values_at("singular", "plural")
    missing = [singular, plural].reject { |w| table.include?(w) }
    unless missing.empty?
      warn "  skipped #{singular}/#{plural} -- not in table: #{missing.join(", ")}"
      next
    end

    row = { "singular" => singular, "plural" => plural, "form" => pair["form"] }
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

def provenance(table, slice_mode)
  checksum = File.exist?(CHECKSUM) ? File.read(CHECKSUM).lines.first.to_s.split.first : nil
  {
    "source" => "https://nlp.stanford.edu/data/glove.6B.zip",
    "entry" => "glove.6B.50d.txt",
    "table_sha256" => checksum,
    "read_from" => slice_mode ? "vectors-slice.txt" : "data/glove.6B.50d.txt",
    "vocabulary" => table.size,
    "dimensions" => table.dims,
    "words_yml_sha256" => Digest::SHA256.file(WORDS).hexdigest,
    "slice_sha256" => File.exist?(SLICE) ? Digest::SHA256.file(SLICE).hexdigest : nil,
    "ruby" => RUBY_VERSION
  }
end

slice_mode = ARGV.include?("--slice")
config = Kit::TinyYAML.load_file(WORDS)
path = slice_mode ? SLICE : TABLE
abort "no table at #{path}; run scripts/fetch.rb first" unless File.exist?(path)

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
warn "loading #{File.basename(path)}"
table = Vectors::Table.load(path)
warn format("  %d words, %d dimensions, %.1fs", table.size, table.dims,
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)

warn "plural direction: #{config["direction_test"].length} held-out pairs"
direction = {
  "provenance" => provenance(table, slice_mode),
  "seed" => config["direction_seed"],
  "training" => config["direction_training"],
  "pairs" => direction_rows(table, config)
}

if slice_mode
  committed_path = File.join(RESULTS, "direction.json")
  abort "nothing committed at #{committed_path} to check against" unless File.exist?(committed_path)

  committed = JSON.parse(File.read(committed_path))
  if committed["pairs"] == direction["pairs"]
    warn "slice reproduces results/direction.json exactly (#{direction["pairs"].length} pairs)"
    exit 0
  end

  differing = committed["pairs"].zip(direction["pairs"]).reject { |x, y| x == y }
  warn "MISMATCH on #{differing.length} pairs; first: #{differing.first.inspect}"
  exit 1
end

File.write(File.join(RESULTS, "direction.json"), "#{JSON.pretty_generate(direction)}\n")

warn "analogies: #{config["analogies"].length} quadruples x #{METRICS.length} metrics"
analogy = { "provenance" => provenance(table, slice_mode), "analogies" => analogy_rows(table, config["analogies"]) }
File.write(File.join(RESULTS, "analogy.json"), "#{JSON.pretty_generate(analogy)}\n")

warn format("done in %.1fs", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
