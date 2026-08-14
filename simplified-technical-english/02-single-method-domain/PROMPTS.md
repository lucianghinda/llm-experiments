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
