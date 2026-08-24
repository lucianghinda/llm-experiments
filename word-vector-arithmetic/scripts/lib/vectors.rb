#!/usr/bin/env ruby
# frozen_string_literal: true

# A GloVe table and the four operations the experiments need: look a word up,
# add and subtract vectors, rank the whole vocabulary against a target, and read
# one word's rank out of that ranking. Ruby stdlib only, no gems.
#
# WHY THE HOT LOOPS ARE UGLY. `a.zip(b).sum { ... }` allocates an array per
# word, so 400,000 of them per query. The indexed `while` loops below allocate
# nothing and turn a 40-second scan into a 1-second one. Everywhere outside
# score_all and the arithmetic helpers, ordinary Ruby is used.
#
# LOWER IS ALWAYS CLOSER. Euclidean gives squared distance, cosine gives
# 1 - similarity. Both are minimised at the target, so ranking code never has to
# know which metric produced a score.

require "set"

module Vectors
  module_function

  def sub(a, b)
    a.each_with_index.map { |x, i| x - b[i] }
  end

  def add(a, b)
    a.each_with_index.map { |x, i| x + b[i] }
  end

  def dot(a, b)
    total = 0.0
    i = 0
    while i < a.length
      total += a[i] * b[i]
      i += 1
    end
    total
  end

  def norm(a) = Math.sqrt(dot(a, a))

  def mean(list)
    sums = Array.new(list.first.length, 0.0)
    list.each do |v|
      i = 0
      while i < sums.length
        sums[i] += v[i]
        i += 1
      end
    end
    sums.map { |s| s / list.length }
  end

  # A scored vocabulary. Built once per target so that the top-n list and a
  # single word's rank come from the same scan rather than two.
  class Ranking
    def initialize(table, scores, exclude, restrict = nil)
      @table = table
      @scores = scores
      @excluded = exclude.filter_map { |w| table.index_of(w) }.to_set
      # nil means the whole vocabulary competes. A set means only those indices
      # do -- how "which of GPT-2's tokens could a GloVe answer even be?" is
      # asked without pretending the other tokens are not there.
      @restrict = restrict
    end

    def eligible?(index)
      !@excluded.include?(index) && (@restrict.nil? || @restrict.include?(index))
    end

    def top(n)
      @scores.each_with_index
             .select { |_, i| eligible?(i) }
             .min_by(n) { |score, _| score }
             .map { |score, i| [@table.word_at(i), score] }
    end

    # Rank counts strictly-closer words, so a tie resolves in the word's favour.
    # Ties in float distance over 400k words are vanishingly rare; the choice is
    # documented rather than relied on.
    def rank_of(word)
      target = @table.index_of(word) or return nil

      mine = @scores[target]
      closer = 0
      i = 0
      while i < @scores.length
        closer += 1 if @scores[i] < mine && eligible?(i)
        i += 1
      end
      closer + 1
    end
  end

  class Table
    DIMS = 50

    attr_reader :dims

    def self.load(path)
      words = []
      vectors = []
      File.foreach(path) do |line|
        parts = line.split(" ")
        # A gensim-exported table opens with a "400000 50" header line. Two
        # integers and nothing else is that header. The rule cannot test against
        # DIMS, because a GPT-2 slice carries 768 of them.
        next if parts.length == 2 && parts.all? { |part| part.match?(/\A\d+\z/) }

        words << parts.shift
        vectors << parts.map!(&:to_f)
      end
      new(words, vectors)
    end

    def initialize(words, vectors)
      @words = words
      @vectors = vectors
      @index = words.each_with_index.to_h
      @dims = vectors.first&.length || DIMS
    end

    def size = @words.length
    def raw_index_of(token) = @index[token]
    def vector_at(index) = @vectors[index]
    def each_word_with_index(&block) = @words.each_with_index(&block)
    def [](word) = (i = @index[word.downcase]) && @vectors[i]
    def include?(word) = @index.key?(word.downcase)
    def index_of(word) = @index[word.downcase]
    def word_at(index) = @words[index]
    def fetch(word) = self[word] || raise(KeyError, "#{word.inspect} is not in this table")

    # Scoring the vocabulary is the expensive step, so it is exposed: an analogy
    # is ranked twice, once with its input words in the running and once
    # without, and both rankings come from one scan.
    def scores(target, metric: :euclidean)
      case metric
      when :euclidean then euclidean_scores(target)
      when :cosine then cosine_scores(target)
      else raise ArgumentError, "unknown metric #{metric.inspect}"
      end
    end

    def ranking(target, metric: :euclidean, exclude: [], restrict: nil)
      ranking_from(scores(target, metric: metric), exclude: exclude, restrict: restrict)
    end

    def ranking_from(scores, exclude: [], restrict: nil)
      Ranking.new(self, scores, exclude, restrict)
    end

    private

    def euclidean_scores(target)
      dims = @dims
      @vectors.map do |v|
        sum = 0.0
        j = 0
        while j < dims
          d = v[j] - target[j]
          sum += d * d
          j += 1
        end
        sum
      end
    end

    def cosine_scores(target)
      dims = @dims
      target_norm = Vectors.norm(target)
      norms = row_norms
      @vectors.each_with_index.map do |v, i|
        sum = 0.0
        j = 0
        while j < dims
          sum += v[j] * target[j]
          j += 1
        end
        denominator = norms[i] * target_norm
        denominator.zero? ? 1.0 : 1.0 - (sum / denominator)
      end
    end

    def row_norms
      @row_norms ||= @vectors.map { |v| Vectors.norm(v) }
    end
  end
end
