# Experiment 4: a whole query object

Date of run: 2026-08-04

## What is under test

The file `app/services/edition/draft_query.rb` from the short-ruby-bookmarks Rails
app, a private codebase.

130 lines. A verbatim copy is in `00-source-draft_query.rb`.

In the prompts below, `<app-root>` is the checkout directory of that app. It was
an absolute path in the real run.

## Why this one

This is the size control against experiment 1. The Rails concern in experiment 1 was 95
lines and its difficulty was **control flow**: callback ordering, an `around_action`, and a
hand-dispatched rescue handler.

This file is a similar size and its difficulty is completely different. It is **data
shaping**: two nearly parallel query branches for two platforms, eager loading to avoid
N+1s, memoised exclusion lists, thread grouping, and a section bucketing step at the end.

The question this experiment asks: does the effect of the style instruction depend on what
kind of complexity is being explained? A wordy paragraph about callback ordering and a wordy
paragraph about query shaping may not fail in the same way.

It also contains the `build_blocks` method from experiment 2, so the two experiments can be
compared directly: the same method explained alone, and explained as part of a whole file.

## The prompts

Base sentence, identical in all six runs:

```
Read the file app/services/edition/draft_query.rb in this Rails app and explain to me
... how it works.
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

### Codex sessions

```
codex exec -C <app-root> \
  -s read-only --skip-git-repo-check \
  -o codex-N-<variant>.md \
  "Read the file app/services/edition/draft_query.rb in this Rails app and explain to me <style clause> how it works."
```

Run sequentially.

## Runs

This whole set was executed twice with byte-identical prompts. Only the output path
changed. Run 1 is in `run-1/`, run 2 is in `run-2/`. The repeat exists to separate real
effects from single-sample noise.

## Output files


Every `.md` output in this folder is the raw, unedited final message from that run.
