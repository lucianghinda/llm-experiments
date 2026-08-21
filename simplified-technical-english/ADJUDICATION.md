# Reading the outputs instead of grepping them

`coverage.rb` decides whether a fact appears in an output by matching a regular expression.
Those expressions were written from the vocabulary of ordinary technical prose. ASD-STE100
exists to replace that vocabulary. So the checker and the treatment are pulling against each
other, and some of the "content cost" the README reports is the checker failing to recognise
a fact that is plainly there.

This file records what happened when the outputs were read instead.

## Method, and its limits

- Every cell the regex marked as a **miss** was read by hand and judged again.
- The standard used is the same one the regexes were built to test: **is the topic addressed
  in substance, in any wording?** Not "is it explained correctly", and not a stricter bar than
  the regex applies. Where the output only implies a fact without stating it, the miss stands.
- Regex **hits** were not systematically re-checked, so false positives mostly survive. One was
  found by accident and is recorded below, which means there are probably others.
- `coverage.rb` itself is unchanged. The tables in the README are still the regex tables, so
  they stay comparable across all three runs. This file is the correction layer, not a
  replacement instrument.

Consequence: these adjudicated numbers can only move **up** from the regex numbers, except
where a false positive was found. They are a ceiling-corrected reading, not an independent
measurement.

## What the regexes get wrong

Four distinct failure modes turned up, and only the first is about Simplified English.

**1. The fact is named by jargon the style rules forbid.** This is the big one, and it hits
ASD-STE100 hardest on experiment 4, whose facts are named `N+1`, "memoised" and "exclusive
range".

| Fact | Regex wants | What the output actually said |
|---|---|---|
| `includes()` avoids N+1 queries | `n\+1\|eager\|includes\(` | "This prevents a large quantity of small queries." |
| exclusion lists are memoised | `memoi\|memoz\|@_excluded\|\|\|=` | "Each of the four methods keeps its result in an instance variable. Thus the database operation occurs one time only." |
| date window is an exclusive range | `\.\.\.\|exclusive\|beginning_of_day` | "The range stops at 00:00 on the day after the end date." |
| unknown section keys are skipped | `skip\|unknown\|not recognis\|...` | "If the section key is not in the `Hash`, the method ignores the block." |

**2. A near-miss synonym.** The regex lists one phrasing and the output uses another that means
the same thing: "the loop **would** not stop" against a pattern wanting "does not stop";
"**never** stops" against the same; "removes the fraction part" against "no fraction";
"never touches the database" against "does not touch the database"; "never moves to the rear"
against "never rewinds".

**3. Inline code splits the phrase.** `moves \`k\` forward` does not match `/moves forward/`.
This one is not about style at all: it hits the control runs too.

**4. A line break splits the phrase.** One Simple Technical English output wrote "The division
is integer\n   division", and `/integer division/` does not match across the newline.

A false positive was also found, in the other direction: experiment 1's "replay skips the rate
limit callback" matches `/rate.?limit/`, and Codex's run-3 control matches it only because it
lists "rate-limit headers" among the cached headers. It never says the replay skips the
callback. That cell was scored down.

## Claude, runs 1 and 2: what the correction does to the published numbers

Totals out of 24. Only regex misses were re-read.

| | run-1 regex | run-1 read | run-2 regex | run-2 read |
|---|---|---|---|---|
| control | 23 | **24** | 24 | 24 |
| Simple Technical English | 21 | **24** | 22 | **24** |
| ASD-STE100 | 14 | **17** | 11 | **17** |

Where the ASD-STE100 corrections came from:

| Cell | Regex | Read | Why |
|---|---|---|---|
| 01 run-1 | 3 | 3 | all three misses are real: no concurrency note, no `created_at`, no Set-Cookie |
| 01 run-2 | 4 | 4 | both misses real |
| 02 run-1 | 2 | 3 | the subtraction is there as "the method removes the root record from the sorted list"; `public_send`, section and in-memory really are absent |
| 02 run-2 | 1 | 2 | "sorts at two levels" is there as "puts the records in order of time" plus "puts all the blocks in order" |
| 03 run-1 | 5 | 5 | miss is real |
| 03 run-2 | 4 | 5 | "integer division" is there as "divides two integers and gives an integer" |
| 04 run-1 | 4 | 6 | both misses are paraphrases (see the table above) |
| 04 run-2 | 2 | 6 | all four misses are paraphrases |

The two Simple Technical English corrections are both on experiment 3 and are both failure
mode 2 or 4, not vocabulary: the outputs say "never stops" and "The division is integer\ndivision".

## What this does to the README's conclusions

- **"For Claude, Simple Technical English is close to free" gets stronger.** Read rather than
  grepped it is not close to free, it is free: 24 of 24 in both runs, the same as the control,
  while halving sentence length.
- **"The formal standard name costs content" survives, at roughly half the size.** 24 against
  17 and 17, not 24 against 14 and 11.
- **The stated reason for that cost is wrong.** The README says compliance with a 53-rule
  standard crowds out the analysis. If that were the mechanism the loss would be spread over
  all four targets. It is not. Experiment 4, the largest and densest file, loses nothing at all
  once read. The whole real loss sits in experiments 1 and 2, and it takes a specific form:
  the ASD-STE100 outputs omit facts that are **named by a domain or API word** — `public_send`,
  `Set-Cookie`, the section rule, the array subtraction. Those are exactly the words a writer
  following a controlled-vocabulary rule has no approved way to discuss.

## Run 3, read rather than grepped

Run 3 is the escape-hatch run. Every cell was scored twice: once by `coverage.rb`, once by
reading every regex miss. Totals out of 24.

| Arm | Variant | Regex | Read |
|---|---|---|---|
| Claude | control | 23 | **24** |
| Claude | ASD-STE100, inline | 15 | **23** |
| Claude | ASD-STE100 + escape hatch | 23 | **24** |
| Claude | ASD-STE100, trailing, no hatch | 19 | **21** |
| Codex | control | 17 | 17 |
| Codex | ASD-STE100, inline | 8 | **13** |
| Codex | ASD-STE100 + escape hatch | 16 | **18** |
| Codex | ASD-STE100, trailing, no hatch | 9 | **14** |

The Codex control is the one cell where the correction went both ways and cancelled out:
experiment 1 gained "created_at" (the entry list says "Creation time", the regex wanted the
symbol) and lost "replay skips the rate limit callback", which it had only matched because the
words "rate-limit headers" appear in a list of cached headers.

### What this does to the escape-hatch result

On the regex instrument the escape hatch looks like a cure: Claude 15 to 23, Codex 8 to 16.
Read instead, most of that gap was never a real loss.

- **For Claude the escape hatch buys almost nothing on content, because there was little to
  buy.** Plain ASD-STE100 already covered 23 of 24. The escape hatch reaches 24. That is one
  fact, in one run.
- **For Codex it is a real gain.** 13 to 18, and 18 is the only ASD-STE100 cell in the run that
  passes its own control's 17.
- **Neither costs the style win.** See the README table: the escape-hatch cell is the most
  consistent compressor in the study.

### Borderline calls, recorded so they can be argued with

- **"linear cost / k never rewinds"** counts only where the output states that `k` never moves
  back. Merely narrating "it moves `k` forward to the next matched character" does not count,
  because every output says that — it is the code. Under the loose reading the fact stops
  discriminating between cells at all.
- **"created_at stored but never read"** is treated as the mention test its regex actually is.
  No output in the whole study says the field is never read, so the strict reading would zero
  the fact everywhere.
- **"array subtraction uses AR equality"** counts where the output says the root is taken out of
  the list. "thread_members holds all the other records" describes the result, not the removal,
  and does not count.
- **"runs in memory, not in SQL"** counts where the output says where the work happens.
  "The caller reads the records from the database before the call" is about the caller, and does
  not count.

## What should change in the instrument

Nothing yet, deliberately. Widening the regexes until they accept paraphrases is the same
motion as tuning an instrument until it agrees with you, and the three existing runs would stop
being comparable with each other. The honest options are to keep `coverage.rb` frozen and treat
this file as its erratum, or to replace fact-matching with fact-reading for every run at once.

What is not defensible is quoting the regex content numbers without this file next to them.
