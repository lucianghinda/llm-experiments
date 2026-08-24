#!/usr/bin/env ruby
# frozen_string_literal: true

# Cuts the committed slice out of a full table.
#
#   ruby word-vector-arithmetic/scripts/slice.rb
#   ruby word-vector-arithmetic/scripts/slice.rb --model gpt2
#   ruby word-vector-arithmetic/scripts/slice.rb --model gpt2 --check
#
# WHY A SLICE EXISTS. data/ is gitignored, so without this the repository would
# hold results nobody can reproduce without a 163MB or 147MB download. The
# direction test only ever reads the words words.yml names, so those rows are
# committed and that experiment runs from a clean clone. The analogy experiment
# cannot be sliced -- ranking the whole vocabulary is the measurement -- so it
# stays download-only and its output is committed instead.
#
# ROWS ARE COPIED, NEVER REFORMATTED. GloVe rows are copied as source text and
# GPT-2 rows as source bytes. Parsing floats and printing them back would round
# somewhere and the slice would stop agreeing with the table it came from.
# `run.rb --slice` checks that agreement by rerunning the whole direction test
# off the slice and demanding identical numbers, which only works while the
# bytes match.

require "digest"
require "json"
require_relative "lib/models"
require_relative "../../containers/scripts/lib/kit"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
WORDS = File.join(EXPERIMENT_DIR, "words.yml")

def option(name, default)
  index = ARGV.index("--#{name}")
  index ? ARGV.fetch(index + 1) : default
end

def wanted_words(config)
  words = config["analogies"].flat_map { |q| q.values_at("a", "b", "c", "d") }
  pairs = [config["direction_seed"]] + config["direction_training"] + config["direction_test"]
  words += pairs.flat_map { |p| p.values_at("singular", "plural") }
  words.map(&:downcase).uniq.sort
end

def glove_slice(wanted, paths)
  lookup = wanted.to_h { |w| [w, nil] }
  File.foreach(paths[:table]) do |line|
    word = line[/\A\S+/]
    lookup[word] = line if lookup.key?(word) && lookup[word].nil?
  end
  missing = lookup.select { |_, line| line.nil? }.keys
  found = lookup.reject { |_, line| line.nil? }
  [{ paths[:slice] => found.keys.sort.map { |w| found[w] }.join }, missing, found.length]
end

def gpt2_slice(wanted, paths)
  table = Models.load("gpt2")
  resolved = wanted.to_h { |word| [word, table.resolve(word)] }
  missing = resolved.select { |_, hit| hit.nil? }.keys
  tokens = resolved.values.compact.map(&:last).uniq.sort

  columns = table.dims
  row_bytes = columns * 4
  # Read the bytes back out of the tensor rather than repacking the parsed
  # floats, so the slice is literally a copy of the source rows.
  bytes = tokens.map do |token|
    index = table.raw_index_of(token)
    File.binread(paths[:table], row_bytes, index * row_bytes)
  end.join

  meta = {
    "source" => File.basename(paths[:table]),
    "tensor_sha256" => Digest::SHA256.file(paths[:table]).hexdigest,
    "columns" => columns,
    "tokens" => tokens
  }
  [{ paths[:slice] => bytes, paths[:slice_meta] => "#{JSON.pretty_generate(meta)}\n" }, missing, tokens.length]
end

model = option("model", "glove")
abort "unknown model #{model.inspect}" unless Models::ALL.include?(model)

check_only = ARGV.include?("--check")
config = Kit::TinyYAML.load_file(WORDS)
wanted = wanted_words(config)
paths = Models.paths(model)

absent = Models.required(model).reject { |path| File.exist?(path) }
unless absent.empty?
  hint = model == "gpt2" ? "scripts/fetch_gpt2.rb" : "scripts/fetch.rb"
  abort "missing #{absent.map { |p| File.basename(p) }.join(", ")}; run #{hint} first"
end

contents, missing, rows = model == "gpt2" ? gpt2_slice(wanted, paths) : glove_slice(wanted, paths)

warn "words.yml names #{wanted.length} words; #{model} covers #{wanted.length - missing.length}"
warn "MISSING from #{model}: #{missing.join(", ")}" unless missing.empty?

if check_only
  stale = contents.reject { |path, body| File.exist?(path) && File.binread(path) == body }
  if stale.empty?
    warn "slice matches the table (#{rows} rows)"
    exit 0
  end
  abort "stale or absent: #{stale.keys.map { |p| File.basename(p) }.join(", ")}; re-run without --check"
end

contents.each { |path, body| File.binwrite(path, body) }
warn "wrote #{contents.keys.map { |p| "#{File.basename(p)} (#{File.size(p)} bytes)" }.join(", ")}"
