# Exact prompts used in this experiment

Date of run: 2026-08-04

## The code under test

`app/controllers/concerns/idempotency.rb` from the postcraftstudio Rails app, a
private codebase.

A verbatim copy is saved here as `00-source-idempotency.rb` (95 lines).

In the prompts below, `<app-root>` is the checkout directory of that app and
`<...>` is the output folder. Both were absolute paths in the real run.

## Experiment design

Six runs. Three with Claude subagents (Opus 5, `general-purpose` agent type), three
with Codex CLI 0.146.0 sessions.

The base task sentence is identical in all six runs. The only thing that changes is the
style clause:

| Variant | Style clause inserted |
|---|---|
| 1. Control | none |
| 2. Simple Technical English | `in Simple Technical English` |
| 3. ASD-STE100 | `in ASD-STE100 Simplified Technical English` |

Nothing else varies. No style examples were provided, no dictionary, no rule list. The
model only gets the name of the thing.

---

## Claude subagent prompts

All three were dispatched with the `Agent` tool, `subagent_type: general-purpose`, run in
parallel in a single message.

### claude-1-control.md

```
Read the file app/controllers/concerns/idempotency.rb in the Rails app at
<app-root> and
explain to me how it works.

Write ONLY your explanation to this exact path: <...>/claude-1-control.md

Do not add a preamble, do not add meta commentary about the task, do not describe what you
are about to do. The file must contain only the explanation itself. Do not modify any file
inside the postcraftstudio codebase. When done, reply with just the word: done
```

### claude-2-simple-technical-english.md

```
Read the file app/controllers/concerns/idempotency.rb in the Rails app at
<app-root> and
explain to me in Simple Technical English how it works.

Write ONLY your explanation to this exact path: <...>/claude-2-simple-technical-english.md

Do not add a preamble, do not add meta commentary about the task, do not describe what you
are about to do. The file must contain only the explanation itself. Do not modify any file
inside the postcraftstudio codebase. When done, reply with just the word: done
```

### claude-3-asd-ste100.md

```
Read the file app/controllers/concerns/idempotency.rb in the Rails app at
<app-root> and
explain to me in ASD-STE100 Simplified Technical English how it works.

Write ONLY your explanation to this exact path: <...>/claude-3-asd-ste100.md

Do not add a preamble, do not add meta commentary about the task, do not describe what you
are about to do. The file must contain only the explanation itself. Do not modify any file
inside the postcraftstudio codebase. When done, reply with just the word: done
```

Note: the "write only your explanation" paragraph is identical in all three and exists only
so the output file is clean. It says nothing about style.

---

## Codex CLI prompts

All three run non-interactively with the working directory set to the postcraftstudio app,
sandbox `read-only`, and the final message captured with `--output-last-message`.

### codex-1-control.md

```
codex exec \
  -C <app-root> \
  -s read-only --skip-git-repo-check \
  -o codex-1-control.md \
  "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me how it works."
```

### codex-2-simple-technical-english.md

```
codex exec \
  -C <app-root> \
  -s read-only --skip-git-repo-check \
  -o codex-2-simple-technical-english.md \
  "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me in Simple Technical English how it works."
```

### codex-3-asd-ste100.md

```
codex exec \
  -C <app-root> \
  -s read-only --skip-git-repo-check \
  -o codex-3-asd-ste100.md \
  "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me in ASD-STE100 Simplified Technical English how it works."
```

---

## What is in each output file

Every `.md` output file in this folder is the raw, unedited final message from that run.
Nothing was reworded, trimmed, or reformatted. The file-path links, the em-dashes and any
formatting quirks are exactly what the model produced.

## Caveats worth stating

1. One run per variant. This is an observation, not a benchmark.
2. Both agents read a codebase that has its own `CLAUDE.md` / `AGENTS.md` files, which may
   carry their own instructions about tone. That was left in place on purpose because it is
   the real working condition.
3. The Claude subagents were told to write to a file, the Codex runs were not. That is a
   small asymmetry in the harness, not in the question asked.

---

## Run 3: the escape hatch (2026-08-20)

`run-3/` tests one new instruction:

> Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning.

The question it asks is whether the escape hatch keeps the short sentences that
ASD-STE100 produces without the loss of content that came with them in runs 1 and 2.

### Why there are two new variants and not one

That clause is a whole sentence, so it cannot sit in the `...` slot that variants 2 and 3
use. It has to follow the base sentence. Position is therefore a second difference and not
only wording, so run 3 adds a fifth variant that puts **plain** ASD-STE100 in exactly the
same trailing position. Variant 5 is the control for position. Variant 4 measured against
variant 5 is the escape hatch on its own.

| Variant | File | Instruction |
|---|---|---|
| 1. Control | `*-1-control.md` | (nothing) |
| 3. ASD-STE100, inline | `*-3-asd-ste100.md` | `in ASD-STE100 Simplified Technical English` in the `...` slot |
| 4. ASD-STE100, trailing, escape hatch | `*-4-asd-ste100-escape-hatch.md` | base sentence, then `Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning.` |
| 5. ASD-STE100, trailing, no escape hatch | `*-5-asd-ste100-trailing.md` | base sentence, then `Use ASD-STE100 Simplified Technical English (STE).` |

Variant 2, Simple Technical English, was not re-run. Run 3 asks only about the ASD-STE100
cell, which is the one that lost facts.

### Why variants 1 and 3 were re-run rather than reused

Both agents changed between 2026-08-04 and 2026-08-20. Codex CLI went from 0.146.0 to
0.148.0 and the Claude model moved too. A control from August 4 cannot be scored against a
variant from August 20, because a difference could be the clause or could be the model.
Run 3 carries its own control for that reason.

### Codex commands

Run sequentially. Unlike runs 1 and 2 the `-o` path is absolute, so no output file is ever
written inside the app checkout.

```
codex exec -C <app-root> -s read-only --skip-git-repo-check \
  -o <...>/run-3/codex-1-control.md \
  "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me how it works."

codex exec -C <app-root> -s read-only --skip-git-repo-check \
  -o <...>/run-3/codex-3-asd-ste100.md \
  "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me in ASD-STE100 Simplified Technical English how it works."

codex exec -C <app-root> -s read-only --skip-git-repo-check \
  -o <...>/run-3/codex-4-asd-ste100-escape-hatch.md \
  "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me how it works. Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning."

codex exec -C <app-root> -s read-only --skip-git-repo-check \
  -o <...>/run-3/codex-5-asd-ste100-trailing.md \
  "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me how it works. Use ASD-STE100 Simplified Technical English (STE)."
```

### Claude subagent prompts

`Agent` tool, `subagent_type: general-purpose`, model Opus 5, all four dispatched in
parallel. The control prompt in full:

```
Read the file app/controllers/concerns/idempotency.rb in the Rails app at
<app-root> and
explain to me how it works.

Write ONLY your explanation to this exact path: <...>/run-3/claude-1-control.md

Do not add a preamble, do not add meta commentary about the task, do not describe what you
are about to do. The file must contain only the explanation itself. Do not modify any file
inside the postcraftstudio codebase. When done, reply with just the word: done
```

The other three change the first paragraph exactly as the table above says, and the output
filename. Everything after the base sentence is byte-identical in all four.

### One edit was made to the run-3 Codex outputs

Codex 0.148.0 writes file links as absolute paths; 0.146.0 wrote them relative. That put the
private checkout location into all 16 run-3 Codex files, which this repo does not carry. The
checkout prefix was replaced with `<app-root>`, the same marker the prompts use, by exact
string substitution. Nothing else was touched: no wording, no structure, no line breaks. The
measurements were re-run afterwards and every number is identical, because `measure.rb` strips
link targets before counting and no fact regex matches a path.

The Claude run-3 outputs needed no edit.
