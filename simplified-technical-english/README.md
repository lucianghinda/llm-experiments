# Experiments: does "Simple Technical English" change how agents explain code?

Four targets, six variants each, repeated twice, plus an independent Codex-only third arm,
plus a later run that tests an escape-hatch instruction. **92 runs total.** The first three
arms ran on 2026-08-04, run 3 on 2026-08-20.

- `run-1/` and `run-2/` are the full six-variant sets, executed by me. Run 2 used
  byte-identical prompts to run 1, only the output path changed, to separate real effects
  from single-sample noise.
- `run-native/` is the **Codex arm only**, executed by Codex itself rather than by my
  harness. See `RUN-NATIVE-PROVENANCE.md` for what that does and does not control. The
  Claude cells show `.` in every table because that arm was not run.
- `run-3/` tests an escape-hatch instruction 16 days later, on newer models. It carries its
  own control, because both agents changed in between, and a **placement control**, so the
  escape hatch can be told apart from the fact that the instruction had to move out of the
  task sentence. Simple Technical English was not re-run there.

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

Run 3 adds two more. Neither fits the `...` slot, so both follow the base sentence:

| Variant | Sentence added after the task |
|---|---|
| 4. ASD-STE100 + escape hatch | `Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning.` |
| 5. ASD-STE100, trailing | `Use ASD-STE100 Simplified Technical English (STE).` |

Variant 5 exists only so variant 4 can be read: it holds the position constant and removes the
escape hatch, so the wording and the placement are not confounded.

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

- `perfact.rb <target> <run>` prints the per-fact yes/no grid for one cell group, which is
  what `coverage.rb` totals up. This is what produces the worked examples below.

Combined output is in `METRICS-ALL.txt` and `COVERAGE-ALL.txt`. `ADJUDICATION.md` records what
those same outputs score when the regex misses are read by hand instead, and why the two
numbers differ.

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

## Run 3: does an escape hatch stop the content loss?

Run 3 asks the question that finding 4 below raises. If naming a 53-rule standard makes
compliance the task, does giving the model permission to break the standard where it hurts keep
the short sentences without the loss of content?

Both agents had changed since 2026-08-04, so run 3 re-runs its own control and its own plain
ASD-STE100 rather than scoring against August's. Codex CLI went from 0.146.0 to 0.148.0 and ran
`gpt-5.6-sol` at `xhigh` reasoning effort. The Claude arm is Opus 5 `general-purpose` subagents
as before, but a later model than in August. Neither August invocation recorded a model name,
so the size of that change is not known and run 3 is not a third sample of runs 1 and 2. It is
its own within-run comparison.

One edit was made to the run-3 Codex outputs: 0.148.0 writes file links as absolute paths where
0.146.0 wrote them relative, so the checkout prefix was replaced with `<app-root>` in all 16
files. Nothing else was changed and every number is identical either way. Each `PROMPTS.md`
records this.

### Style

Average words per sentence, share of sentences over the 25-word limit in brackets.

| Target | Claude ctrl | Claude ASD | Claude ASD+hatch | Claude ASD trailing |
|---|---|---|---|---|
| 01 concern | 15.8 (16%) | 10.3 (0%) | **10.1** (0%) | 12.3 (4%) |
| 02 method, domain | 16.7 (17%) | 11.5 (4%) | **10.1** (2%) | 9.4 (0%) |
| 03 method, algorithm | 15.7 (11%) | 10.5 (2%) | **9.7** (0%) | 11.2 (0%) |
| 04 query object | 16.6 (11%) | 11.9 (3%) | **10.8** (1%) | 10.0 (0%) |

| Target | Codex ctrl | Codex ASD | Codex ASD+hatch | Codex ASD trailing |
|---|---|---|---|---|
| 01 concern | 12.3 (0%) | 10.9 (3%) | 9.0 (0%) | 11.1 (4%) |
| 02 method, domain | 16.7 (11%) | 9.5 (0%) | 11.2 (0%) | 9.5 (0%) |
| 03 method, algorithm | 9.9 (0%) | 8.4 (0%) | 9.2 (0%) | 8.5 (0%) |
| 04 query object | 12.1 (4%) | 9.1 (0%) | 11.2 (0%) | 8.7 (0%) |

The escape hatch does not buy back the long sentences. It compresses at least as hard as plain
ASD-STE100 in every cell where the two can be compared, it lands in the tightest band of any
variant in run 3 — 9.7 to 10.8 words per sentence across the four Claude targets, against 10.3
to 11.9 for plain ASD-STE100 — and it shortens Codex in four cells out of four. Four cells is
not many, so read the tightness as suggestive and the direction as solid.

Claude's control held its house style on the new model, 15.7 to 16.7 words per sentence, and
the no-overlap result held with it: the lowest control was 15.7 and the highest instructed cell
was 12.3.

### Content, measured two ways

Out of 24. The left number is `coverage.rb`. The right number is what those same outputs score
when every regex miss is read by hand, which is the subject of `ADJUDICATION.md`.

| Variant | Claude regex | Claude read | Codex regex | Codex read |
|---|---|---|---|---|
| control | 23 | 24 | 17 | 17 |
| ASD-STE100, inline | 15 | 23 | 8 | 13 |
| ASD-STE100 + escape hatch | 23 | **24** | 16 | **18** |
| ASD-STE100, trailing, no hatch | 19 | 21 | 9 | 14 |

### The answer

**On the checker the escape hatch looks like a cure. Read, most of the disease was the
checker.**

- **For Claude it buys about one fact.** Plain ASD-STE100 already covered 23 of 24 on this
  model once read. The hatch reaches 24. That is one fact in one run, which is noise.
- **For Codex it is a real gain.** 13 to 18, and 18 is the only ASD-STE100 cell in the run that
  beats its own control's 17.
- **It is free.** No style is given up for it, in either arm.
- **The placement control earned its place.** Moving the instruction into a trailing sentence
  without the escape hatch scored 21 read for Claude and 14 for Codex — no better than leaving
  it inline. So what helps is the escape-hatch wording, not the new position.

Practical reading: the clause is worth using, because it costs nothing and it removes a real
failure mode on the weaker arm. But the dramatic before-and-after on the fact counts is mostly
an artifact, and it should not be quoted on its own.

## The fact checker is biased against the treatment

This is the most important thing run 3 turned up, and it is not about the escape hatch.

`coverage.rb` decides whether a fact is present by matching a regular expression written from
the vocabulary of ordinary technical prose. ASD-STE100 exists to replace that vocabulary. The
checker therefore marks an output down for following the instruction under test.

Experiment 4's run-2 ASD-STE100 cell is published above as **2 of 6**. Read, it contains all
six. `N+1` is there as "This prevents a large quantity of small queries", memoisation as "keeps
its result in an instance variable… one time only", the exclusive range as "The range stops at
00:00 on the day after the end date".

Re-reading every regex miss in runs 1 and 2 moves the Claude numbers out of 24:

| | run-1 regex | run-1 read | run-2 regex | run-2 read |
|---|---|---|---|---|
| control | 23 | 24 | 24 | 24 |
| Simple Technical English | 21 | **24** | 22 | **24** |
| ASD-STE100 | 14 | **17** | 11 | **17** |

`ADJUDICATION.md` holds the per-cell verdicts, the quotes behind each one, the four distinct
ways the regexes fail, the one false positive found in the other direction, and the borderline
calls. The regex tables above are left exactly as they were, so all four runs stay comparable
with each other.

## What replicated

1. **Claude's control sentence length is a house style, not a response to the code.** Eight
   runs across four unrelated kinds of code, all between 16.3 and 19.6 words per sentence.
2. **Either style clause roughly halves it, with zero overlap.** This is the strongest result
   in the set.
3. **For Claude, "Simple Technical English" is free.** 21 and 22 facts by the checker against a
   control of 23 and 24 — and 24 against 24 once the outputs are read rather than matched,
   while halving sentence length. This was written as "close to free" after two runs; the
   correction made it stronger, not weaker.
4. **The formal standard name costs content, at about half the size first reported, and not for
   the reason I gave.** ASD-STE100 scored 14 then 11 by the checker, but 17 and 17 read. My
   original reading was that compliance with a 53-rule standard crowds out the analysis. That
   does not survive: if it did, the loss would be spread over all four targets, and it is not.
   Experiment 4 loses nothing once read. The whole real loss sits in experiments 1 and 2, and
   it takes a specific shape — the ASD-STE100 outputs drop facts that are **named by a domain
   or API word**, `public_send`, `Set-Cookie`, the section rule, the array subtraction. Those
   are the facts a controlled vocabulary gives you no approved way to say.
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
  that it was explained correctly — and they miss it entirely when it is mentioned in words
  they do not list, which is exactly what a style instruction causes. See
  `ADJUDICATION.md`. Treat every content number above as a floor, and a floor that is lower
  for the instructed variants than for the controls.
- **Both codebases contain their own `CLAUDE.md` and `AGENTS.md` files** which may carry
  their own tone instructions. These were left in place deliberately, because that is the
  real working condition.
- **The Claude runs were told to write their answer to a file and the Codex runs were not.**
  That is an asymmetry in the harness, not in the question asked.
