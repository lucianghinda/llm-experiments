#!/usr/bin/env ruby
# frozen_string_literal: true

# Where each model's vectors come from, full table or committed slice.
#
# ONE PLACE DECIDES WHAT A MODEL IS. run.rb, slice.rb and report.rb all need to
# agree on file names, on which slice format a model uses, and on whether a
# ranking has a candidate pool. Spreading that across three scripts is how the
# GloVe path and the GPT-2 path quietly stop being the same experiment.
#
# THE SLICE FORMAT FOLLOWS THE SOURCE FORMAT. GloVe ships text, so its slice is
# the source lines copied verbatim. GPT-2 ships float32, so its slice is those
# bytes copied verbatim, with the token strings beside them in JSON. Either way
# nothing is reparsed and reprinted, so a slice cannot drift from the table in
# the last decimal place.

require "json"
require_relative "vectors"
require_relative "gpt2"

module Models
  EXPERIMENT_DIR = File.expand_path("../..", __dir__)
  DATA_DIR = File.join(EXPERIMENT_DIR, "data")
  ALL = %w[glove gpt2].freeze

  module_function

  def paths(model)
    case model
    when "glove"
      { table: File.join(DATA_DIR, "glove.6B.50d.txt"),
        slice: File.join(EXPERIMENT_DIR, "vectors-slice.txt") }
    when "gpt2"
      { table: File.join(DATA_DIR, "gpt2-wte.f32"),
        vocab: File.join(DATA_DIR, "gpt2-vocab.json"),
        meta: File.join(DATA_DIR, "gpt2-wte.meta.json"),
        slice: File.join(EXPERIMENT_DIR, "vectors-slice-gpt2.f32"),
        slice_meta: File.join(EXPERIMENT_DIR, "vectors-slice-gpt2.json") }
    else
      raise ArgumentError, "unknown model #{model.inspect}; expected one of #{ALL.join(", ")}"
    end
  end

  def available?(model, slice: false)
    required(model, slice: slice).all? { |path| File.exist?(path) }
  end

  def required(model, slice: false)
    p = paths(model)
    if slice
      model == "gpt2" ? [p[:slice], p[:slice_meta]] : [p[:slice]]
    else
      model == "gpt2" ? [p[:table], p[:vocab], p[:meta]] : [p[:table]]
    end
  end

  def load(model, slice: false)
    p = paths(model)
    case [model, slice]
    in ["glove", false] then Vectors::Table.load(p[:table])
    in ["glove", true] then Vectors::Table.load(p[:slice])
    in ["gpt2", false] then Gpt2.load(p[:table], p[:vocab], p[:meta])
    in ["gpt2", true] then load_gpt2_slice(p[:slice], p[:slice_meta])
    end
  end

  def load_gpt2_slice(path, meta_path)
    meta = JSON.parse(File.read(meta_path))
    columns = meta["columns"]
    bytes = File.binread(path)
    vectors = meta["tokens"].each_index.map do |i|
      bytes.byteslice(i * columns * 4, columns * 4).unpack("e#{columns}")
    end
    Gpt2::Table.new(meta["tokens"], vectors)
  end

  # nil means every entry competes in a ranking. GPT-2 gets a pool because most
  # of its vocabulary is fragments that no word-level answer could be.
  def candidate_pool(model, table)
    model == "gpt2" ? table.word_like_indices : nil
  end
end
