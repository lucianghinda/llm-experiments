#!/usr/bin/env ruby
# Per-fact yes/no grid for one target and one run. This is what produces the
# worked-example tables in the README; coverage.rb only reports totals.
#
# Usage: ruby perfact.rb 04-query-object run-3
#
# A "yes" means the regex in coverage.rb matched. It does not mean the fact is
# there, and a "--" does not mean it is absent: see ADJUDICATION.md for what
# happens when the outputs are read instead of matched.

src = File.read(File.join(__dir__, "coverage.rb"))
eval(src[/^VARIANTS = \{.*?^\}/m])
eval(src[/^CHECKS = \{.*?^\}\n/m])

dir, run = ARGV
abort "usage: ruby perfact.rb <target-dir> <run-dir>" unless dir && run
checks = CHECKS.fetch(dir) { abort "unknown target #{dir}" }

present = VARIANTS.select { |file, _| File.exist?(File.join(__dir__, dir, run, file)) }
abort "no outputs in #{dir}/#{run}" if present.empty?
texts = present.to_h { |file, label| [label, File.read(File.join(__dir__, dir, run, file))] }

W = 9
puts "#{dir} / #{run}"
puts format("%-42s %s", "fact", texts.keys.map { |k| k.rjust(W) }.join(" "))
puts "-" * (43 + texts.size * (W + 1))

scores = Hash.new(0)
checks.each do |name, pattern|
  cells = texts.map do |label, text|
    hit = text.match?(pattern)
    scores[label] += 1 if hit
    (hit ? "yes" : "--").rjust(W)
  end
  puts format("%-42s %s", name, cells.join(" "))
end

puts "-" * (43 + texts.size * (W + 1))
puts format("%-42s %s", "SCORE (out of #{checks.size})", texts.keys.map { |k| scores[k].to_s.rjust(W) }.join(" "))
