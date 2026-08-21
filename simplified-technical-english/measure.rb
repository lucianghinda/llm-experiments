#!/usr/bin/env ruby
# Measures prose complexity of every explanation output.
# Code fences, tables and inline code are stripped so we only measure prose.
#
# Usage: ruby measure.rb            # every experiment, every run
#        ruby measure.rb 01-rails-concern

TARGETS = if ARGV.empty?
  Dir.glob(File.join(__dir__, "[0-9][0-9]-*")).select { |p| File.directory?(p) }.sort
else
  ARGV.map { |a| File.expand_path(a, __dir__) }
end

# ASDw is ASD-STE100 asked for in a trailing sentence that carries an escape hatch,
# "when it doesn't detract from meaning". ASDt is the same trailing sentence without
# the escape hatch, so the wording and the position can be told apart.
VARIANTS = {
  "claude-1-control.md" => "cl-ctrl",
  "claude-2-simple-technical-english.md" => "cl-STE",
  "claude-3-asd-ste100.md" => "cl-ASD",
  "claude-4-asd-ste100-escape-hatch.md" => "cl-ASDw",
  "claude-5-asd-ste100-trailing.md" => "cl-ASDt",
  "codex-1-control.md" => "cx-ctrl",
  "codex-2-simple-technical-english.md" => "cx-STE",
  "codex-3-asd-ste100.md" => "cx-ASD",
  "codex-4-asd-ste100-escape-hatch.md" => "cx-ASDw",
  "codex-5-asd-ste100-trailing.md" => "cx-ASDt"
}

# Words an engineer would not say out loud when pointing at this file.
# NOTE: this list was built from experiment 01's vocabulary, so a zero reading
# elsewhere is weak evidence rather than proof that no jargon appeared.
JARGON = %w[
  machinery layering semantics contract orchestrate orchestrates orchestration
  deliberate deliberately encoded namespaced fingerprint fingerprints degrades
  tradeoff tradeoffs subtle engages engage dispatches dispatch installed
  propagates propagate reconstruction snapshot corrupting namespace
  deterministic explicit implicitly conceptually notably essentially
  fail-open best-effort atomic reservation quota convention consequence
]

def prose(text)
  t = text.dup
  t.gsub!(/```.*?```/m, " ")             # fenced code
  t.gsub!(/^\s*\|.*$/, " ")              # markdown tables
  t.gsub!(/^\s*#+.*$/, " ")              # headings
  t.gsub!(/`[^`]*`/, "CODE")             # inline code becomes one token
  t.gsub!(/\[([^\]]*)\]\([^)]*\)/, '\1') # links keep their label
  t
end

def sentences(text)
  text.split(/(?<=[.!?])\s+/).map(&:strip).reject { |s| s.split(/\s+/).size < 3 }
end

def stats(path)
  raw = File.read(path)
  body = prose(raw)
  sents = sentences(body)
  words = body.split(/\s+/).reject { |w| w.gsub(/\W/, "").empty? }
  lens = sents.map { |s| s.split(/\s+/).size }

  jargon = body.downcase.scan(/[a-z-]+/).count { |w| JARGON.include?(w) }

  {
    words: words.size,
    sentences: sents.size,
    avg: lens.empty? ? 0.0 : (lens.sum.to_f / lens.size).round(1),
    max: lens.max || 0,
    over_25_pct: lens.empty? ? 0 : (100.0 * lens.count { |l| l > 25 } / lens.size).round,
    jargon: jargon
  }
end

W = 11 # column width: ten variants have to fit on one line

def cell(s)
  return ".".rjust(W) unless s

  format("%5.1f (%2d%%)", s[:avg], s[:over_25_pct]).rjust(W)
end

TARGETS.each do |target|
  runs = Dir.glob(File.join(target, "run-*")).select { |p| File.directory?(p) }.sort
  next if runs.empty?

  puts "== #{File.basename(target)}"
  puts format("%-8s %s", "run", VARIANTS.values.map { |v| v.rjust(W) }.join(" "))
  puts "-" * (9 + VARIANTS.size * (W + 1))

  collected = {}
  runs.each do |run|
    row = VARIANTS.keys.map do |file|
      path = File.join(run, file)
      s = File.exist?(path) ? stats(path) : nil
      collected[[File.basename(run), file]] = s
      cell(s)
    end
    puts format("%-8s %s", File.basename(run), row.join(" "))
  end

  # words / jargon detail per run
  puts
  puts format("%-8s %s", "words", VARIANTS.values.map { |v| v.rjust(W) }.join(" "))
  runs.each do |run|
    row = VARIANTS.keys.map do |file|
      s = collected[[File.basename(run), file]]
      (s ? "#{s[:words]}w j#{s[:jargon]}" : ".").rjust(W)
    end
    puts format("%-8s %s", File.basename(run), row.join(" "))
  end
  puts
end

puts "avg words per sentence (share of sentences over the 25-word STE limit)"
puts "words row: prose word count, and jargon-list hits as jN"
