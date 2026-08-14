# Experiment 3: a single method, domain-free

Date of run: 2026-08-04

## What is under test

The method `count_transpositions` in `app/services/authors/match_by_name.rb` from the
short-ruby-bookmarks Rails app, a private codebase.

12 lines. A verbatim copy is in `00-source-count_transpositions.rb`.

In the prompts below, `<app-root>` is the checkout directory of that app. It was
an absolute path in the real run.

## Why this one

This is the deliberate opposite of experiment 2. It is a hand-rolled piece of the
Jaro-Winkler string similarity algorithm. There is **no business domain vocabulary in it at
all**: no authors, no names, no matching. Only `string_a`, `string_b`, `k`, and two boolean
arrays.

The question this experiment asks: my complaint was that the model invents abstractions
instead of using the domain words already in the code. So what happens when there are no
domain words to use? Does asking for simpler English still help, or does it have nothing to
grab onto?

The method is also genuinely tricky. The `k += 1 until matches_b[k]` line walks a second
cursor through the matched positions of the other string, and the final `transpositions / 2`
is integer division that halves the count because every transposition is counted twice.

## The prompts

Base sentence, identical in all six runs:

```
Read the method `count_transpositions` in app/services/authors/match_by_name.rb in this
Rails app and explain to me ... how it works.
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
  "Read the method `count_transpositions` in app/services/authors/match_by_name.rb in this Rails app and explain to me <style clause> how it works."
```

Run sequentially.

## Runs

This whole set was executed twice with byte-identical prompts. Only the output path
changed. Run 1 is in `run-1/`, run 2 is in `run-2/`. The repeat exists to separate real
effects from single-sample noise.

## Output files


Every `.md` output in this folder is the raw, unedited final message from that run.
