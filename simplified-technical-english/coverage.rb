#!/usr/bin/env ruby
# Checks which non-obvious facts about each target survive each style variant.
#
# For 02, 03 and 04 the facts were chosen by reading the source file first,
# before reading any output, so the checklist is not just "whatever the control
# run happened to say". For 01 the control output had already been read when the
# checklist was written, so that block is weaker evidence than the other three.
# Each fact is matched by a regex over the output text.
#
# Usage: ruby coverage.rb

VARIANTS = {
  "claude-1-control.md" => "cl-ctrl",
  "claude-2-simple-technical-english.md" => "cl-STE",
  "claude-3-asd-ste100.md" => "cl-ASD",
  "codex-1-control.md" => "cx-ctrl",
  "codex-2-simple-technical-english.md" => "cx-STE",
  "codex-3-asd-ste100.md" => "cx-ASD"
}

CHECKS = {
  "01-rails-concern" => {
    "no lock on concurrent first requests" => /no lock|without a lock|no in-flight|concurren|same moment|simultaneous|at the same time/i,
    "created_at stored but never read"     => /created_at/i,
    "Set-Cookie kept out of the cache"     => /set-cookie/i,
    "replay skips the rate limit callback" => /rate.?limit|quota/i,
    "5xx deliberately not cached"          => /5xx|500 or more|status of 500|not cache.{0,40}(server|5)/im,
    "streaming responses are skipped"      => /stream|chunked|enumerator/i
  },
  "02-single-method-domain" => {
    "fallback root when real root missing" => /fallback|\|\| ordered_records\.first|no record (passes|obeys)|if no record/i,
    "why public_send and not &symbol"      => /public_send/i,
    "root record decides the section"      => /section/i,
    "sorts at two levels"                  => /sort/i,
    "array subtraction uses AR equality"   => /- \[root\]|subtract|equality|==/i,
    "runs in memory, not in SQL"           => /in memory|memory|does not (run in |touch the )?(sql|database)|no database/i
  },
  "03-single-method-algorithm" => {
    "divide by two because swaps count twice" => /divid|\/ 2|two differences|counted twice|double/i,
    "integer division floors the result"      => /integer division|floor|no fraction/i,
    "unbounded until loop would spin forever" => /forever|infinite|without a limit|does not stop|no bound/i,
    "worked example with real strings"        => /martha|marhta|"ab"|"ba"|jon|jno/i,
    "relies on count_matches invariant"       => /count_matches/i,
    "linear cost / k never rewinds"           => /linear|never rewind|only ever moves forward|forward only|moves forward/i
  },
  "04-query-object" => {
    "includes() avoids N+1 queries"        => /n\+1|eager|includes\(/i,
    "exclusion lists are memoised"         => /memoi|memoz|@_excluded|\|\|=/i,
    "excluding a thread root drops thread" => /root exclusion|thread root|without_.*root|excluded_.*thread_roots/i,
    "date window is an exclusive range"    => /\.\.\.|exclusive|tomorrow\.beginning_of_day|beginning_of_day/i,
    "unknown section keys are skipped"     => /next unless sections\.key|skip|unknown|not recognis|does not (contain|have) the (key|section)/i,
    "two platform branches are parallel"   => /bluesky/i
  }
}

GRAND = Hash.new { |h, k| h[k] = Hash.new(0) }

CHECKS.each do |dir, checks|
  path = File.join(__dir__, dir)
  next unless File.directory?(path)

  runs = Dir.glob(File.join(path, "run-*")).select { |p| File.directory?(p) }.sort
  next if runs.empty?

  puts "== #{dir}  (#{checks.size} facts per cell)"
  puts format("%-10s %s", "run", VARIANTS.values.map { |v| v.rjust(8) }.join(" "))
  puts "-" * (11 + VARIANTS.size * 9)

  runs.each do |run|
    run_name = File.basename(run)
    totals = {}

    VARIANTS.each do |file, label|
      full = File.join(run, file)
      next unless File.exist?(full)

      text = File.read(full)
      totals[label] = checks.each_value.count { |pattern| text.match?(pattern) }
      GRAND[run_name][label] += totals[label]
    end

    cells = VARIANTS.values.map { |v| (totals.key?(v) ? totals[v].to_s : ".").rjust(8) }
    puts format("%-10s %s", run_name, cells.join(" "))
  end
  puts
end

puts "== TOTAL across all experiments (24 facts per run; . means that arm was not run)"
puts format("%-10s %s", "run", VARIANTS.values.map { |v| v.rjust(8) }.join(" "))
puts "-" * (11 + VARIANTS.size * 9)
GRAND.keys.sort.each do |run|
  cells = VARIANTS.values.map { |v| (GRAND[run].key?(v) ? GRAND[run][v].to_s : ".").rjust(8) }
  puts format("%-10s %s", run, cells.join(" "))
end
