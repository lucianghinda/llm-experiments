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
