# Experiments: does "Simple Technical English" change how agents explain code?

Four targets, six variants each, repeated twice, plus an independent Codex-only third arm.
**60 runs total.** Run on 2026-08-04.

- `run-1/` and `run-2/` are the full six-variant sets, executed by me. Run 2 used
  byte-identical prompts to run 1, only the output path changed, to separate real effects
  from single-sample noise.
- `run-native/` is the **Codex arm only**, executed by Codex itself rather than by my
  harness. See `RUN-NATIVE-PROVENANCE.md` for what that does and does not control. The
  Claude cells show `.` in every table because that arm was not run.

## The question

When I ask an agent to explain unfamiliar code, Claude tends to reach for complex words,
abstractions and invented terms instead of the domain words already present in the code.

Does adding a style clause to the prompt fix that, and what does it cost?

## The design

Every run uses the same base sentence. Only the style clause changes:

| Variant | Clause added |
|---|---|
| 1. Control | (nothing) |
| 2. Simple Technical English | `in Simple Technical English` |
| 3. ASD-STE100 | `in ASD-STE100 Simplified Technical English` |

No examples, no rule list, no dictionary is ever provided. The model only gets the name.

Two agents per variant: a Claude subagent (Opus 5, `general-purpose`) and a Codex CLI 0.146.0
session (`codex exec`, sandbox `read-only`).

## The four targets

| # | Folder | Target | Size | Chosen because |
|---|---|---|---|---|
| 1 | `01-rails-concern` | `Idempotency` concern, postcraftstudio | 95 lines | Control-flow complexity: callback ordering and a hand-dispatched rescue handler |
| 2 | `02-single-method-domain` | `build_blocks`, short-ruby-bookmarks | 11 lines | Smallest unit, and **dense with domain words** already in the code (thread, root, block, section) |
| 3 | `03-single-method-algorithm` | `count_transpositions`, short-ruby-bookmarks | 12 lines | Same size as #2 but **no domain vocabulary at all**, pure Jaro-Winkler arithmetic |
| 4 | `04-query-object` | `Edition::DraftQuery`, short-ruby-bookmarks | 130 lines | Size control against #1, but data-shaping complexity instead of control flow |

Experiments 2 and 3 are a matched pair: same scale, opposite amounts of domain vocabulary.
Experiment 4 contains the method from experiment 2, so the same code can be compared alone
and in context.

Each folder holds its own `PROMPTS.md` with the exact prompts, the verbatim source under
test as `00-source-*.rb`, and two run folders with six raw unedited outputs each.

## Scripts

- `measure.rb` measures prose only, after stripping code fences, tables and headings.
  Reports words, sentence count, average and maximum sentence length, the share of sentences
  over the 25-word ASD-STE100 limit for descriptive text, and hits against a jargon word list.
  Run with no arguments to measure every folder.
- `coverage.rb` checks which non-obvious facts about each target appear in each output. For
  experiments 2, 3 and 4 the six facts were chosen by reading the source **before** reading
  any output, so the checklist is not simply "whatever the control run happened to say". For
  experiment 1 the control output had already been read when the checklist was written, so
  that row is weaker evidence than the other three.

Combined output is in `METRICS-ALL.txt` and `COVERAGE-ALL.txt`.

## Results: style

Average words per sentence. Each cell holds two separate measurements, run 1 then run 2, with
the share of sentences over 25 words in brackets. `18.6 / 17.4` means run 1 averaged 18.6 words
per sentence and run 2 averaged 17.4.

| Target | Claude ctrl | Claude STE | Claude ASD | Codex ctrl | Codex STE | Codex ASD |
|---|---|---|---|---|---|---|
| 01 concern | 18.6 / 17.4 | 8.1 / 8.3 | 9.7 / 9.8 | 11.7 / 13.9 | 10.7 / 11.4 | 9.6 / 8.3 |
| 02 method, domain | 16.9 / 19.3 | 9.1 / 8.8 | 10.2 / 10.3 | 10.7 / 13.8 | 15.1 / 19.4 | 9.3 / 9.9 |
| 03 method, algorithm | 17.5 / 16.3 | 9.3 / 9.9 | 9.0 / 10.3 | 11.9 / 10.5 | 13.9 / 11.1 | 8.3 / 8.9 |
| 04 query object | 19.6 / 17.0 | 10.7 / 9.4 | 11.0 / 10.6 | 12.2 / 15.0 | 11.0 / 11.5 | 8.3 / 8.3 |

The headline number, across all 24 Claude runs:

| | range over 8 runs |
|---|---|
| Claude, no style clause | **16.3 to 19.6** words per sentence |
| Claude, either style clause (16 runs) | **8.1 to 10.7** words per sentence |

Not one control run went below 16.3. Not one instructed run went above 10.7. There is no
overlap at all between the two distributions.

Counting each variant against its own control in the same run:

| | shortened its control | lengthened it |
|---|---|---|
| Claude, Simple TE (8 runs) | 8 | 0 |
| Claude, ASD-STE100 (8 runs) | 8 | 0 |
| Codex, ASD-STE100 (12 runs) | 12 | 0 |
| Codex, Simple TE (12 runs) | 8 | **4** |

Claude's deltas run from 6.0 to 10.6 words per sentence shorter, with no exceptions. Codex's
ASD-STE100 also shortens every time. Codex's Simple TE is the only cell in the study that
goes both ways, once landing at 19.4 words per sentence against a 13.8 control.

## Results: content

Each target has six facts, so **every cell is a score out of 6** and every total is out of 24.

Run 1:

| Target | Claude ctrl | Claude STE | Claude ASD | Codex ctrl | Codex STE | Codex ASD |
|---|---|---|---|---|---|---|
| 01 concern | 6 | 6 | 3 | 4 | 2 | 2 |
| 02 method, domain | 5 | 6 | 2 | 3 | 1 | 1 |
| 03 method, algorithm | 6 | 3 | 5 | 4 | 2 | 4 |
| 04 query object | 6 | 6 | 4 | 6 | 2 | 3 |
| **total out of 24** | **23** | **21** | **14** | **17** | **7** | **10** |

Run 2:

| Target | Claude ctrl | Claude STE | Claude ASD | Codex ctrl | Codex STE | Codex ASD |
|---|---|---|---|---|---|---|
| 01 concern | 6 | 6 | 4 | 3 | 1 | 3 |
| 02 method, domain | 6 | 6 | 1 | 4 | 1 | 1 |
| 03 method, algorithm | 6 | 4 | 4 | 4 | 3 | 2 |
| 04 query object | 6 | 6 | 2 | 2 | 5 | 2 |
| **total out of 24** | **24** | **22** | **11** | **13** | **10** | **8** |

Worked example, experiment 4, the same six facts scored against four Claude outputs. Run
`ruby coverage.rb` for the full per-fact grid.

```
fact                                     ctrl r1  ctrl r2   ASD r1   ASD r2
---------------------------------------------------------------------------
includes() avoids N+1 queries                yes      yes       --       --
exclusion lists are memoised                 yes      yes       --       --
excluding a thread root drops thread         yes      yes      yes      yes
date window is an exclusive range            yes      yes      yes       --
unknown section keys are skipped             yes      yes      yes       --
two platform branches are parallel           yes      yes      yes      yes
---------------------------------------------------------------------------
SCORE (out of 6)                               6        6        4        2
```

The independent Codex arm, for comparison against the two Codex columns above:

| | run-1 | run-2 | run-native |
|---|---|---|---|
| Codex control | 17 | 13 | 13 |
| Codex Simple TE | 7 | 10 | 6 |
| Codex ASD-STE100 | 10 | 8 | 7 |

## What replicated

1. **Claude's control sentence length is a house style, not a response to the code.** Eight
   runs across four unrelated kinds of code, all between 16.3 and 19.6 words per sentence.
2. **Either style clause roughly halves it, with zero overlap.** This is the strongest result
   in the set.
3. **For Claude, "Simple Technical English" is close to free.** 21 and 22 facts against a
   control of 23 and 24, while halving sentence length.
4. **The formal standard name costs content, and the second run made this worse.** ASD-STE100
   scored 14 then 11 facts. My reading is that naming a 53-rule standard makes compliance the
   task, and the analysis gets cut to make room.
5. **For Codex, both clauses cost content, confirmed by a third party.** Control scored
   17, 13 and 13; Simple TE 7, 10 and 6; ASD-STE100 10, 8 and 7. The third column came from
   Codex running its own arm, so this no longer depends on my harness.
6. **Simple TE does not reliably compress Codex.** In 4 of 12 runs it made Codex's sentences
   longer than its own control, once by a lot (19.4 words per sentence on experiment 2).
   ASD-STE100, by contrast, shortened Codex in all 12.

## What did NOT replicate

Both of these were single-cell findings in run 1 that the repeat killed. They are recorded
here because they are the reason the second run was worth doing.

1. **The experiment 3 "reversal".** In run 1, ASD-STE100 beat Simple TE on the pure algorithm,
   5 facts to 3, and I had a tidy explanation ready about algorithms having fewer facts to
   lose. Run 2 came back 4 to 4. It was noise.
2. **"Simpler did not mean shorter".** In run 1, experiment 4's Simple TE output was 1744
   prose words against the control's 1453. Run 2 gave 1369 against 1415, the other way round.
   What does survive is the restructuring: at a similar word count, the Simple TE output has
   roughly twice as many sentences as the control.

## A counting error, corrected

After two runs this README claimed Simple TE made Codex's sentences longer "in five of eight
runs". That was wrong on the data I already had: it was 4 of 8, and across all three runs it
is 4 of 12. The count is now produced by script rather than by eye. Recorded here because the
wrong number told a cleaner story than the right one, which is exactly why it survived a
reading.

## Caveats

- **Two runs per cell.** Enough to tell stable effects from noise, not enough for confidence
   intervals. Still an observation, not a benchmark.
- **Codex's control is noisy on content**, 17 then 13 of 24. Its individual cells move more
  between runs than Claude's do, so the Codex conclusions are held with less confidence than
  the Claude ones.
- **The jargon word list was built from experiment 1's vocabulary**, so its zero readings on
  experiments 2 and 3 are weak evidence rather than proof that no jargon appeared there.
  Its absolute counts also move a lot between runs (26 then 14 on experiment 1's control),
  so treat the direction as meaningful and the magnitude as not.
- **The fact checklists are regex matches**, so they detect that a topic was mentioned, not
  that it was explained correctly.
- **Both codebases contain their own `CLAUDE.md` and `AGENTS.md` files** which may carry
  their own tone instructions. These were left in place deliberately, because that is the
  real working condition.
- **The Claude runs were told to write their answer to a file and the Codex runs were not.**
  That is an asymmetry in the harness, not in the question asked.
