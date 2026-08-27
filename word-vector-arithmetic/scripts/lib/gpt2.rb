#!/usr/bin/env ruby
# frozen_string_literal: true

# GPT-2's token embedding matrix, loaded as a Vectors::Table.
#
# TOKENS ARE NOT WORDS, AND HERE THAT STOPS BEING A SLOGAN. GPT-2 has no bare
# "queen" token at all -- only "Ġqueen", the form a word takes mid-sentence,
# where Ġ is how byte-level BPE writes a leading space. Same for mice,
# criterion and phenomenon. So a word-level experiment has to choose a token
# for each word, and the choice is: prefer the space-prefixed form, fall back to
# the bare one. Every result records which form it used, because that choice is
# an assumption, not a detail.
#
# THE CANDIDATE POOL IS THE OTHER CHOICE. GloVe's 400k entries are all words.
# GPT-2's 50257 are mostly not -- they are fragments, punctuation and byte
# escapes that no GloVe ranking could ever return. Ranking against all of them
# and ranking against the word-like ones only are different experiments, so
# run.rb does both rather than picking the flattering one.

require "json"
require_relative "vectors"

module Gpt2
  module_function

  # byte-level BPE writes every byte as a printable character. This is the
  # inverse of that table: character back to byte.
  def byte_decoder
    @byte_decoder ||= begin
      bytes = (33..126).to_a + (161..172).to_a + (174..255).to_a
      printable = bytes.dup
      spare = 0
      (0..255).each do |byte|
        next if bytes.include?(byte)

        bytes << byte
        printable << 256 + spare
        spare += 1
      end
      bytes.zip(printable).to_h { |byte, code| [code.chr(Encoding::UTF_8), byte] }
    end
  end

  # A BPE token can be half a multi-byte character, so decoding does not always
  # produce valid UTF-8. Those get an explicit <0x..> spelling of their bytes.
  # The obvious fallback -- keep the raw byte-level form -- collides: GPT-2
  # writes byte 225 as the character "\u00e1", and a different token decodes to
  # exactly that character, so 51 pairs of rows would have shared one name.
  # Losing uniqueness collapses two rows of the embedding matrix into one
  # lookup, so Gpt2.load asserts it rather than assuming it.
  def decode(token)
    decoder = byte_decoder
    text = token.chars.map { |char| decoder.fetch(char, "?".ord) }.pack("C*").force_encoding("UTF-8")
    text.valid_encoding? ? text : "<0x#{text.unpack1("H*")}>"
  end

  def load(tensor_path, vocab_path, meta_path)
    meta = JSON.parse(File.read(meta_path))
    rows, columns = meta["shape"]

    vocabulary = JSON.parse(File.read(vocab_path))
    tokens = Array.new(rows) { |i| "<unused-#{i}>" }
    vocabulary.each { |token, id| tokens[id] = decode(token) if id < rows }

    vectors = Array.new(rows)
    row_bytes = columns * 4
    File.open(tensor_path, "rb") do |file|
      rows.times do |i|
        chunk = file.read(row_bytes) or raise "tensor ended at row #{i} of #{rows}"

        vectors[i] = chunk.unpack("e#{columns}")
      end
    end

    duplicates = tokens.length - tokens.uniq.length
    raise "#{duplicates} token spellings collide after decoding" if duplicates.positive?

    Table.new(tokens, vectors)
  end

  # A Vectors::Table whose entries are tokens, with the word-to-token policy and
  # the word-like pool attached.
  class Table < Vectors::Table
    WORD_LIKE = /\A [A-Za-z]+\z/

    # GloVe is lowercased, GPT-2 is not, so a word has up to four plausible
    # tokens. BOTH MID-SENTENCE FORMS COME BEFORE EITHER LINE-INITIAL ONE.
    # Preferring lowercase first looks natural and is wrong: there is no
    # " rome" token, so "rome" won -- the fragment inside "Jerome" and
    # "chrome" -- and the Italy analogy answered " Italian" with " Rome" at
    # rank 42047. Ordering " Rome" ahead of "rome" fixes it. Whichever form
    # wins is recorded with every result, because it is an assumption the
    # comparison rests on.
    def candidate_forms(word)
      capitalised = word.sub(/\A(.)/) { Regexp.last_match(1).upcase }
      [" #{word}", " #{capitalised}", word, capitalised].uniq
    end

    def resolve(word)
      candidate_forms(word).each do |form|
        index = raw_index_of(form)
        return [index, form] if index
      end
      nil
    end

    def index_of(word) = resolve(word)&.first
    def include?(word) = !resolve(word).nil?
    def [](word) = (index = index_of(word)) && vector_at(index)

    # The tokens that could plausibly be a GloVe answer: a whole word as it
    # appears after a space. Everything else is a fragment or punctuation.
    def word_like_indices
      @word_like_indices ||= begin
        found = []
        each_word_with_index { |token, index| found << index if token.match?(WORD_LIKE) }
        found.to_set
      end
    end
  end
end
