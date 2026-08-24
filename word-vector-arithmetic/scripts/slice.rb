#!/usr/bin/env ruby
# frozen_string_literal: true

# Cuts the committed slice out of the full table.
#
#   ruby word-vector-arithmetic/scripts/slice.rb
#   ruby word-vector-arithmetic/scripts/slice.rb --check   # verify, write nothing
#
# WHY A SLICE EXISTS. data/ is gitignored, so without this file the repository
# would hold results nobody can reproduce without a 163MB download. The
# direction test only ever reads the words words.yml names, so those rows are
# committed and that experiment runs from a clean clone. The analogy experiment
# cannot be sliced -- ranking the whole vocabulary is the measurement -- so it
# stays download-only and its output is committed instead.
#
# ROWS ARE COPIED VERBATIM, NEVER REFORMATTED. Parsing the floats and printing
# them back would round the fifth decimal and the slice would stop agreeing with
# the table it came from. `run.rb --slice` checks that agreement by rerunning the
# whole direction test off this file and demanding identical numbers, which only
# works while the bytes match.

require "digest"
require_relative "lib/vectors"
require_relative "../../containers/scripts/lib/kit"

EXPERIMENT_DIR = File.expand_path("..", __dir__)
TABLE = File.join(EXPERIMENT_DIR, "data", "glove.6B.50d.txt")
SLICE = File.join(EXPERIMENT_DIR, "vectors-slice.txt")
WORDS = File.join(EXPERIMENT_DIR, "words.yml")

check_only = ARGV.include?("--check")

def wanted_words(config)
  words = config["analogies"].flat_map { |q| q.values_at("a", "b", "c", "d") }
  pairs = [config["direction_seed"]] + config["direction_training"] + config["direction_test"]
  words += pairs.flat_map { |p| p.values_at("singular", "plural") }
  words.map(&:downcase).uniq.sort
end

config = Kit::TinyYAML.load_file(WORDS)
wanted = wanted_words(config)
abort "no table at #{TABLE}; run scripts/fetch.rb first" unless File.exist?(TABLE)

lookup = wanted.to_h { |w| [w, nil] }
File.foreach(TABLE) do |line|
  word = line[/\A\S+/]
  lookup[word] = line if lookup.key?(word) && lookup[word].nil?
end

missing = lookup.select { |_, line| line.nil? }.keys
found = lookup.reject { |_, line| line.nil? }

warn "words.yml names #{wanted.length} words; #{found.length} are in the table"
warn "MISSING from GloVe: #{missing.join(", ")}" unless missing.empty?

body = found.keys.sort.map { |w| found[w] }.join
digest = Digest::SHA256.hexdigest(body)

if check_only
  unless File.exist?(SLICE)
    abort "no slice at #{SLICE}"
  end

  current = File.read(SLICE)
  if current == body
    warn "slice matches the table (#{found.length} rows, sha256 #{digest[0, 12]})"
    exit 0
  end
  abort "slice does not match the table; re-run without --check"
end

File.write(SLICE, body)
warn "wrote #{SLICE} (#{found.length} rows, #{File.size(SLICE)} bytes, sha256 #{digest[0, 12]})"
