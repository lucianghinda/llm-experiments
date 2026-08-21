# Experiment 2: a single method, domain-rich

Date of run: 2026-08-04

## What is under test

The method `build_blocks` in `app/services/edition/draft_query.rb` from the
short-ruby-bookmarks Rails app, a private codebase.

11 lines. A verbatim copy is in `00-source-build_blocks.rb`.

In the prompts below, `<app-root>` is the checkout directory of that app. It was
an absolute path in the real run.

## Why this one

This method is dense with domain vocabulary that already exists in the codebase: *thread*,
*root*, *block*, *section*, *members*. The domain words are sitting right there in the
identifiers.

The question this experiment asks: does the model use the words the code already uses, or
does it invent new abstractions for concepts that are already named?

The method also has one genuinely subtle line, the `|| ordered_records.first` fallback,
which handles a thread whose root record is not in the result set.

## The prompts

Base sentence, identical in all six runs:

```
Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app
and explain to me ... how it works.
```

The style clause goes in the `...` position:

| Variant | Style clause |
|---|---|
| 1. Control | (nothing) |
| 2. Simple Technical English | `in Simple Technical English` |
| 3. ASD-STE100 | `in ASD-STE100 Simplified Technical English` |

### Claude subagents

Dispatched with the `Agent` tool, `subagent_type: general-purpose`, all three in parallel.
The prompt is the base sentence above, followed by this identical block in all three runs:

```
Write ONLY your explanation to this exact path: <...>/claude-N-<variant>.md

Do not add a preamble, do not add meta commentary about the task, do not describe what you
are about to do. The file must contain only the explanation itself. Do not modify any file
inside the short-ruby-bookmarks codebase. When done, reply with just the word: done
```

The Claude prompts name the full app path instead of "this Rails app", because a subagent
has no working directory set for it.

### Codex sessions

```
codex exec -C <app-root> \
  -s read-only --skip-git-repo-check \
  -o codex-N-<variant>.md \
  "Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app and explain to me <style clause> how it works."
```

Run sequentially, not in parallel, so the three runs do not contend with each other.

## Runs

This whole set was executed twice with byte-identical prompts. Only the output path
changed. Run 1 is in `run-1/`, run 2 is in `run-2/`. The repeat exists to separate real
effects from single-sample noise.

## Output files


Every `.md` output in this folder is the raw, unedited final message from that run.

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
  "Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app and explain to me how it works."

codex exec -C <app-root> -s read-only --skip-git-repo-check \
  -o <...>/run-3/codex-3-asd-ste100.md \
  "Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app and explain to me in ASD-STE100 Simplified Technical English how it works."

codex exec -C <app-root> -s read-only --skip-git-repo-check \
  -o <...>/run-3/codex-4-asd-ste100-escape-hatch.md \
  "Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app and explain to me how it works. Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning."

codex exec -C <app-root> -s read-only --skip-git-repo-check \
  -o <...>/run-3/codex-5-asd-ste100-trailing.md \
  "Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app and explain to me how it works. Use ASD-STE100 Simplified Technical English (STE)."
```

### Claude subagent prompts

`Agent` tool, `subagent_type: general-purpose`, model Opus 5, all four dispatched in
parallel. The control prompt in full:

```
Read the method `build_blocks` in app/services/edition/draft_query.rb in the Rails app at
<app-root> and
explain to me how it works.

Write ONLY your explanation to this exact path: <...>/run-3/claude-1-control.md

Do not add a preamble, do not add meta commentary about the task, do not describe what you
are about to do. The file must contain only the explanation itself. Do not modify any file
inside the short-ruby-bookmarks codebase. When done, reply with just the word: done
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
