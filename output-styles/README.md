# Experiment: do output styles act like prompt clauses?

**96 runs, executed 2026-09-02.** Claude Code 2.1.258, `claude-opus-5`, one fresh
container per cell. `ruby verify.rb` re-checks every cell for model drift, CLI drift, app
SHA, MCP contamination and correct style delivery, and passes on all 96.

The [`simplified-technical-english/`](../simplified-technical-english/) experiment showed
that a style clause in the prompt halves Claude's sentence length with zero overlap between
the two distributions. But a clause in the prompt is the wrong tool for daily work: it must
be retyped every turn. Claude Code's answer to that is an
[output style](https://code.claude.com/docs/en/output-styles): a Markdown file that
modifies the system prompt for the whole session.

This experiment moves the same instructions into that mechanism, and lines them up against
every built-in style Claude Code ships today.

## The questions

1. **Does the delivery mechanism matter?** The same STE instruction, given once in the
   system prompt as an output style versus given inline in the user prompt. Same words,
   different location. Does the compression band (8–11 words per sentence) and the content
   cost replicate?
2. **How do Anthropic's own five built-in styles score on the same task and the same
   rulers?** In particular: does **Concise** — Anthropic's own brevity style, which
   promises to keep engineering "as thorough as in the Default style" — cost facts the way
   ASD-STE100 did? And does **Explanatory** add facts, or only words?
3. **What does `keep-coding-instructions` do?** A custom style silently *removes* Claude
   Code's built-in software-engineering instructions unless the frontmatter says
   `keep-coding-instructions: true`. That default is what most users will hit first. One
   arm measures it in isolation.

## What an output style actually is (and why the comparison is not pure)

Per the docs, selecting a non-default style does two things: it adds the style's
instructions to the system prompt, **and** it reminds Claude of the style during the
conversation. So arms 6–9 test the mechanism *as shipped* — placement plus reminder —
not placement alone. If an output-style arm beats its prompt-clause twin, this experiment
cannot say which of the two components did it. That is accepted and recorded here rather
than controlled, because "the feature as shipped" is what a user chooses between.

## The design

Same four targets, same base sentence as before:

```
Read the method/concern `<target>` in <path> in this Rails app and explain to me how it works.
```

Twelve variants. Arms 1–9 use that sentence with **no style words in the prompt at all**;
the style arrives only through the `outputStyle` setting. Arms 10–12 are the bridge back to
the earlier experiment: prompt-clause delivery, byte-compatible with the wording used
there, re-run on today's model so the comparison is within-run.

| # | Variant | Delivery | Style words |
|---|---|---|---|
| 1 | Default | control | (none) |
| 2 | Concise | built-in style | Anthropic's |
| 3 | Explanatory | built-in style | Anthropic's |
| 4 | Learning | built-in style | Anthropic's |
| 5 | Proactive | built-in style | Anthropic's |
| 6 | Simple TE | custom style, `keep-coding-instructions: true` | `Use Simple Technical English.` |
| 7 | ASD-STE100 | custom style, `keep-coding-instructions: true` | `Use ASD-STE100 Simplified Technical English (STE).` |
| 8 | ASD-STE100 + escape hatch | custom style, `keep-coding-instructions: true` | `Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning.` |
| 9 | ASD-STE100, bare | custom style, `keep-coding-instructions` **absent** (defaults to false) | same as 7 |
| 10 | Simple TE, prompt clause | `in Simple Technical English` in the `...` slot | run-1 wording |
| 11 | ASD-STE100, prompt clause | `in ASD-STE100 Simplified Technical English` in the `...` slot | run-1 wording |
| 12 | ASD-STE100 + hatch, prompt sentence | trailing sentence after the base | run-3 wording |

The custom style files are committed verbatim in [`styles/`](styles/). Their bodies are
one sentence each — the same name-only treatment as before. No rule list, no dictionary,
no examples. Frontmatter carries only `name`, `description` and (for 6–8) the
`keep-coding-instructions` flag. Variant 9 is byte-identical to variant 7 except that one
frontmatter line is absent, so the flag is the only difference.

**4 targets × 12 variants × 2 runs = 96 runs.** Two runs per cell, byte-identical setup,
same day, because that is what separated real effects from noise last time.

### The pairings that answer the questions

| Comparison | Question it answers |
|---|---|
| 6 vs 10, 7 vs 11, 8 vs 12 | Does moving the instruction from prompt to output style change the effect? |
| 7 vs 9 | What does dropping the coding instructions do, holding the style text constant? |
| 2 vs 6, 2 vs 7 | Concise against the STE family: does Anthropic's brevity style keep more facts? |
| 3 vs 1 | Does Explanatory add checklist facts, or only length? |
| each vs 1 | The style effect itself |

## The harness — and why it must change

Two reasons the earlier subagent harness cannot be reused:

1. **Output styles do not apply to subagents.** The docs are explicit: a subagent runs its
   own system prompt. Every prior STE run was an Opus `general-purpose` subagent. So each
   run here is a fresh **main-loop `claude -p` session**.
2. **My own global `~/.claude/CLAUDE.md` says "Use Simple Technical English."** Subagents
   never saw it. A main-loop session loads it, which would hand the treatment to the
   control arm before the experiment starts. So every run happens in the
   [`containers/`](../containers/) clean room: fresh container, fresh CLI, no user
   CLAUDE.md, no MCP servers, no memory. This deviates from the earlier experiment's
   "real working condition" stance, deliberately, because here the real working condition
   *is* the confound.

The harness is deliberately disk-frugal (the machine ran at 97% full): no per-app
images are built. The apps arrive as git bundles of their `main` branches (10 MB total
against ~5 GB per app image), cloned inside the container at trial start; a newer Claude
CLI than the base image's (the Concise style needs ≥ 2.1.237) is installed once into a
host directory from inside a container and mounted read-only into every trial; each cell
is one `--rm` container, run sequentially, so nothing persists between trials except the
results. Exact mechanics, mounts and invocation flags are in [`PROMPTS.md`](PROMPTS.md);
the scripts are [`scripts/run_grid.rb`](scripts/run_grid.rb) and
[`scripts/trial.rb`](scripts/trial.rb).

Per run, inside the container:

- Custom styles copied into the checkout's `.claude/output-styles/` (variants 6–9 only).
- The style selected via `{"outputStyle": "<name>"}` in the checkout's
  `.claude/settings.local.json`, written before the session starts. Styles are read once
  at session start; each `-p` run is a fresh session, so this is sufficient.
- Invocation: `claude -p "<prompt>" --model opus --output-format json` with a strict
  empty MCP config, output captured from stdout. This removes the earlier harness
  asymmetry where Claude wrote to a file. The `result` field is extracted to the
  committed `.md`; the full JSON is kept alongside for the usage numbers.
- Read-only by construction: `-p` cannot prompt for permission, so writes are denied.
- **Recorded per run: `claude --version`, the app SHA and the model id.** The earlier
  experiment could not name its August models, and paid for it in run 3. Not again.

## Measurement

Same rulers as before, unchanged, so the numbers stay comparable:

- [`../simplified-technical-english/measure.rb`](../simplified-technical-english/measure.rb)
  for prose metrics (words/sentence, share over the 25-word limit, jargon hits).
- The same per-target six-fact checklists via `coverage.rb` — **plus hand adjudication of
  every regex miss, all 116 of them**, in [`ADJUDICATION.md`](ADJUDICATION.md), totalled
  back on by `adjudicate.rb`. The earlier experiment learned late that the regex checker is
  biased against exactly the variants under test. Here both numbers are first-class, and
  the regex number is always reported as a floor.
- **Tokens and cost per run**, from the `--output-format json` usage block. The docs make
  testable claims — Explanatory and Learning increase output tokens, Concise decreases
  them — and this column checks them. All three hold: Concise 1843 output tokens against
  Default's 3377, Explanatory 4980, Learning 3978.
- `verify.rb` re-checks the integrity of all 96 cells and exits non-zero on any problem,
  so a contaminated or half-finished grid cannot pass as a clean one.

## Hypotheses, written before any run

1. STE-as-output-style lands in the same 8–11 words/sentence band as STE-in-prompt, with
   the same zero overlap against control.
2. The output-style arms compress at least as hard as their prompt twins, because the
   mechanism adds a mid-conversation reminder the prompt clause never had.
3. Concise shortens *responses* but not *sentences*: fewer sentences at Default-like
   length, versus STE's many short ones. Different mechanism, and likely a smaller fact
   cost than ASD-STE100's.
4. Explanatory adds words but not checklist facts; the six facts are already near ceiling
   for Default on these targets.
5. Variant 9 (coding instructions dropped) changes behaviour more than any style wording
   does — likely in exploration depth and tool use before the answer, possibly in fact
   coverage.

## Every style was verified active, because a wrong name is silent

An unknown `outputStyle` does not warn. It does not fail. It falls back to Default and
says nothing — not on stderr, and not in `--debug`, whose output was byte-identical for a
valid style and for `"Totally Bogus Style"`. A mistyped cell would therefore read as a
clean null result while actually being a second control run.

Three things close that hole:

1. **A canary style.** A style whose whole body was "always end every response with the
   exact token ZQ7CANARY" was published and run. The token appeared, from both the project
   directory and the user directory, so custom styles demonstrably reach `-p` sessions.
2. **`trial.rb` refuses to run** a custom-style cell whose file frontmatter `name:` does
   not equal the name the setting asks for, and `verify.rb` re-checks all 96 cells after
   the fact.
3. **An introspection probe** for the built-ins, which asked the model whether its system
   prompt tells it to insert `TODO(human)` markers:

   | Style set | Answer |
   |---|---|
   | Learning | YES — quotes its own `Output Style: Learning` section |
   | Explanatory | NO — quotes its own `Output Style: Explanatory` section instead |
   | Default | NO — no output-style section at all |
   | `Totally Bogus Style` | NO — no output-style section at all, i.e. silent fallback |

That probe also explains the one signature that never fired. **Learning produced zero
`TODO(human)` markers in all 8 cells**, but it was active the whole time: its own rule
conditions the marker on generating 20+ lines of code, and this task writes none. The
style is real, the trigger is not met. Explanatory, by contrast, fired its `★ Insight`
block in 8 cells out of 8.

## Results: style

Eight cells per variant, four targets by two runs. Average words per sentence.

Facts are given twice: the `coverage.rb` regex floor, and what those same outputs score
when every miss is read by hand ([`ADJUDICATION.md`](ADJUDICATION.md), 116 misses read,
26 of them real facts in other words). Read the right-hand number.

| Variant | facts regex → read | words/sentence | prose words | vs Default |
|---|---|---|---|---|
| Default | 42 → 42 /48 | 16.1 – 29.0 | 439 | — |
| Concise | 39 → 40 /48 | 15.5 – 22.0 | 323 | −26% |
| Explanatory | 46 → **48** /48 | 17.6 – 23.7 | 715 | +63% |
| Learning | 43 → 44 /48 | 17.6 – 21.5 | 654 | +49% |
| Proactive | 44 → 45 /48 | 15.2 – 23.1 | 496 | +13% |
| Simple TE, as style | 42 → 43 /48 | 13.6 – 19.2 | 468 | +7% |
| ASD-STE100, as style | 35 → 38 /48 | **10.7 – 12.8** | 413 | −6% |
| ASD-STE100 + hatch, as style | 39 → 40 /48 | 13.3 – 16.3 | 450 | +3% |
| ASD-STE100, no coding instructions | 34 → 38 /48 | **9.1 – 12.8** | 419 | −5% |
| Simple TE, as prompt | 39 → 42 /48 | 13.6 – 24.2 | 499 | +14% |
| ASD-STE100, as prompt | 24 → 31 /48 | 9.3 – 13.6 | 510 | +16% |
| ASD-STE100 + hatch, as prompt | 33 → 35 /48 | 10.3 – 14.4 | 459 | +5% |

The correction is largest exactly where the earlier experiment predicted — the instructed
arms, and most of all ASD-STE100 as a prompt clause, which gains 7 facts on being read.
Default gains nothing, because it was already writing in the checker's own vocabulary.
But the correction is **much smaller than in the earlier experiment, and very uneven
across targets**: 78% of the misses on target 04 were real facts, against 5% on target 01.
`ADJUDICATION.md` also records four false positives found by spot-check, all on control-ish
arms, which this correction does not remove. Treat small differences between neighbouring
arms as noise.

Default's 29.0 is a single cell (run-2, target 03) whose answer was mostly code: only 4
prose sentences survived stripping, against a median of 31 across the grid. It is the only
cell below 12 sentences. Excluding it, Default runs **16.1 – 21.4**.

### What replicated, and what did not

**ASD-STE100 replicated, in both deliveries.** Every ASD-STE100 arm sits clear of Default's
stable range with no overlap at all: 10.7–12.8 as a style, 9.3–13.6 as a prompt clause,
against 16.1–21.4. This is the earlier experiment's strongest result, reproduced through a
new mechanism, a new harness and a newer model.

**Simple Technical English did not.** The earlier experiment put Claude at 8.1–10.7 words
per sentence with no overlap against its control. Here it lands at 13.6–19.2 as a style
and 13.6–24.2 as a prompt clause, both overlapping Default heavily. The name alone no
longer buys the compression it used to.

**The `bare` arm suggests why.** The only arm that reaches the old band is the one with
Claude Code's built-in software-engineering instructions removed: 9.1–12.8, the tightest
and lowest in the grid. Every other arm carries those instructions and compresses less.
The earlier experiment ran `general-purpose` subagents, which never load them. So the
best available reading is that **the main-loop system prompt competes with a style
instruction, and dilutes a weak one.** ASD-STE100 is specific enough to survive that;
"Simple Technical English" is not. This is one arm in one experiment, so it is a
direction, not a settled mechanism.

## Results: the three questions

**1. Does the delivery mechanism matter?** For sentence length, no. For content, yes, and
it survives adjudication. On the clean pair the prompt clause compresses harder
(10.3–14.4 against 13.3–16.3) while the output style keeps more facts (**40 against 35**
read). The confounded ASD pair points the same way, 38 against 31. So the same words cost
less content when they arrive as a system-prompt style than when they arrive in the user
turn — a five-fact difference on a 48-fact scale, from two pairs, so a direction rather
than a measured size. Hypothesis 2 is refuted: the style's mid-conversation reminder did
**not** make it compress harder than the same words in the prompt; it compressed less and
preserved more.

**A flaw in these pairings, found after the run.** Only variant 8 against variant 12 uses
byte-identical instruction words. Variants 6/10 and 7/11 differ in wording *as well as*
delivery — `Use X.` in the style file against `in X` in the prompt — because the prompt
arms were written to match the earlier experiment verbatim while the style files were
written to read naturally. Those two pairs therefore cannot separate delivery from
wording, and the eye-catching gap between ASD-STE100 as a style and as a prompt is **not**
a clean delivery result. The clean pair is 8 against 12, and its gap is smaller. This was
the design's own mistake, not a measurement problem.

**2. How do the built-in styles score?**

*Concise behaves exactly as hypothesis 3 predicted, and it is not a brevity style in the
STE sense.* It cuts prose by 26% and output tokens by 45%, but its sentences stay at
Default length (15.5–22.0 against 16.1–21.4). It writes fewer sentences of ordinary
length; ASD-STE100 writes many short ones. Anyone reaching for Concise to get simpler
*sentences* will not get them. Its fact cost by regex is 39/48 against Default's 42.

*Explanatory refutes hypothesis 4, and is the standout result.* Read, it scored **48 out
of 48** — every fact on every target in both runs, the only variant to do so, against
Default's 42. Its extra 63% of words are not padding; they carry facts the control missed.
It pays for that in output tokens, the most of any arm.

*Proactive was not a no-op*, though the task was read-only: 45/48 facts, +13% words. Its
sentence range is the widest in the grid.

**3. What does `keep-coding-instructions` do?** More than any style wording in the
experiment, which is hypothesis 5 confirmed. Dropping it made the *same* ASD-STE100
instruction compress harder, not less — 9.1–12.8 against 10.7–12.8, the tightest band in
the grid — while landing on the same read fact count, 38 either way. It also changed the
agent's behaviour around the answer: turns rose from 3.0 to 3.8 on average, and in one
matched pair from 2 to 6. So the flag is not cosmetic. Leaving it out gives a stronger
style at no measured cost in content and some cost in turns, and leaving it out is the
default.

## What I would actually use

- **Want shorter sentences?** `Use ASD-STE100 Simplified Technical English (STE).` as an
  output style. It is the only instruction here that reliably halves sentence length, it
  costs about four facts out of 48 against Default, and naming the standard is what does
  the work — "Simple Technical English" no longer does.
- **Want shorter answers?** Concise, which is a different thing and worth not confusing
  with the above: a quarter fewer words, 45% fewer output tokens, sentences unchanged, and
  two facts out of 48.
- **Want the most complete explanation?** Explanatory, at 48/48 and the highest token bill
  in the grid.
- **Writing a custom style?** Decide `keep-coding-instructions` deliberately. Leaving it
  out sharpens the style and costs turns; setting it to `true` softens the style. Neither
  is the safe default.
- **Check the name.** A typo silently gives you Default and nothing anywhere says so.

## Caveats accepted at design time

- **No Codex arm.** Output styles are a Claude Code mechanism; there is nothing equivalent
  to hold against it. The bridge arms (10–12) are the only tie back to the two-agent
  tables.
- **Learning could not show its signature.** It is built to leave `TODO(human)` markers,
  and this task writes no code, so the marker never fires. The introspection probe above
  confirms the style was nonetheless loaded, so its cells are real measurements of
  Learning applied to an explain task — not of Learning doing what it is for.
- **Proactive on a read-only explain task** may be a no-op by design; a null result there
  is expected, not interesting.
- **Clean room ≠ daily condition.** The containers strip the ~48k tokens of host context.
  Effects measured here may shrink under a loaded context window; that is a follow-up, not
  this experiment.
- **Arm 6–9 vs 10–12 is placement *plus* reminder**, as discussed above — and, for two of
  the three pairs, placement plus wording as well. See the flaw noted under question 1.
- The four fact checklists were written for the earlier experiment and are reused
  unchanged. For target 1 the checklist was written after reading a control output; that
  weakness carries over.
- **Two runs per cell.** Enough to separate a stable effect from noise, not enough for
  confidence intervals. The single-cell findings here are flagged as such.
- **One outlier cell** (run-2, target 03, Default) has only 4 prose sentences and is
  excluded from the Default range where stated. It is left in the raw tables.
