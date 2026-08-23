---
created: 2026-08-23T05:03:43Z
updated: 2026-08-23T07:30:00Z
branch: experiment/convention-navigation
trigger: manual
restored: false
topic: convention-navigation-design
---

# Handoff: convention-navigation — harness built and verified, grid not run

## Goal

Test the assumption that an agent working on a conventional Rails app spends
fewer tokens and fewer search calls than on the same code in a nonstandard,
config-wired layout. Claude Code and Codex CLI first.

## Current State

- **PR #8 open** on branch `experiment/convention-navigation`. 44 files.
- **The scramble is built and verified.** `scramble_check.rb` passes all nine
  checks: 720 files byte-identical after applying the move manifest, 708
  identifiers with identical counts, `zeitwerk:check` clean on both variants,
  179 identical route lines, and 348 runs / 1011 assertions / 0 failures on
  both. Report committed at `variants/campfire/scramble_check.json`.
- **Image `llmx-conv-campfire:latest` exists**, holding both layouts as
  `trial/v1` (conventional) and `trial/v2` (scrambled). Gems are in a layer
  cached against Gemfile/Gemfile.lock alone, so re-scrambling rebuilds in under
  a minute instead of re-running `bundle install`.
- **A trial runs end to end** with Codex: prompt → agent → answer extraction →
  scripted acceptance → meta.json. Three validation trials passed. Two more
  (the mutation check and the cross-layer check) were running at handoff time.
- **All four acceptance checks validated against real Codex trials**, including
  the cross-layer task on the scrambled layout (agent found `db/changes/`,
  touched model + controller + view partial, suite green at 354 runs) and the
  mutation check (agent's test isolated by name, green with 2 assertions, red
  after the rule was removed). The `scrambled-mapped` condition also works: the
  map is written as `AGENTS.md`/`CLAUDE.md` per agent, committed so the tree is
  clean, 2,487 bytes charged to the trial.
- **The grid has NOT been run.** No RESULTS.md exists. `results/` was
  deliberately deleted so a handful of n=1 validation trials could not be
  mistaken for findings; they remain in the gitignored `results-raw/`.

## Blocked on

**Claude's container credential is dead and needs an interactive re-login:**

```sh
ruby containers/scripts/auth_setup.rb --agent claude
```

The stored refresh token was spent, the replacement was discarded with the
private config copy, and the CLI then blanked the file. `run_trial.rb` now
refuses to start rather than burning cells, and `runner.rb` writes refreshed
credentials back (refusing any downgrade), so this should not recur. Codex is
unaffected and works.

## Key Decisions

- One app in two layouts, never Rails vs another framework — comparing two apps
  confounds language, size, features and training familiarity.
- Whole roots move, nothing below them: every directory under a Zeitwerk root is
  a namespace, so renaming one would rename a constant.
- Two top-level roots (`platform/`, `delivery/`) at unequal depths, because a
  single new parent would be learnable in one `ls` and would measure nothing.
- `test/system/` and `lib/` deliberately do NOT move — see Failed Approaches.
- Prompts contain no path, no layout directory, and no word that greps to ≤3
  files when one is a task target. Ordinary domain words ("room") are allowed
  and necessary; the threshold does the work, not a banned-word list.
- Only successful trials count toward cost; failure rates reported separately.
- 5 repeats, not 3 (this repo has retracted three-run claims).
- Success decided by script always. The test-writing task mutates the rule out
  of the source and requires the agent's test to go red.

## Bug found in at-file-mentions (affects a published experiment)

`runner.rb` listed branches with `git branch --format=%(refname:short)` passed to
Open3 as a string. The parentheses route it through `sh`, where `(` is a syntax
error, so the list came back empty and **no branch was ever deleted**. All 102
published at-file-mentions trials ran with `trial/base` and their bug branch both
present, where `git diff trial/base` would have shown the planted defect — the
exact leak that README claims to have closed.

Every published transcript was re-scanned. Five trials ran a history command, all
`git log --oneline` (which reveals nothing: flattening gave every commit the same
message), and **no trial ran git diff, git show, git branch or anything else that
can compare two refs**. No published result changes.

Both runners now single-quote the format string and abort the trial if more than
the branch under test survives. Fixed in commit 234e701, with the finding
recorded in at-file-mentions/README.md.

## Failed Approaches

- **Host-side verification of the scramble.** `bundle install` for campfire dies
  on a libyaml assertion (bundler 4.0.13, rails from git main). Abandoned for
  the container; do not retry.
- **Moving `test/system` to `test/suite/browser`.** `bin/rails test` excludes
  system tests by a hardcoded path glob, so moved they stopped being excluded
  and the scrambled suite died booting a browser the container lacks. That is a
  change in which tests run, not in layout.
- **Counting grep-coupon words by file count alone.** Flagged ordinary English
  ("exactly", "able"). Tying the rule to the task's target files dropped the
  false positives and caught a real leak: "conversation" appears only in
  `Room`'s comment.
- **Matching targets against the whole Codex event.** It carries the command's
  output, so a `rg` that printed the path scored as arrival. Now matched on the
  locator (command/input) only.

## Files to Read

- `convention-navigation/README.md` — design, verification output, and the
  "things that would have quietly ruined this" list
- `convention-navigation/scramble.yml` — the move rules and why each exception exists
- `convention-navigation/tasks.yml` — the four pilot tasks and their ground truth
- `convention-navigation/scripts/scramble_check.rb` — the proof the variants match

## Next Steps

1. Re-login Claude in the container (`auth_setup.rb --agent claude`), then
   confirm one Claude trial runs.
2. Run the pilot: `run_grid.rb` — 4 tasks × 2 conditions × 2 agents × 5 repeats
   = 80 trials. Sequential; budget several hours.
3. `parse_transcript.rb --all`, then `metrics.rb`, then `sanitize.rb`.
4. Write RESULTS.md against the pre-registered decision rule already in the
   README. Report a mismatch between token totals and search counts as the
   finding if that is what happens.
5. Phase 2 if phase 1 shows an effect: add `scrambled-mapped` (already
   implemented, `--conditions` flag), and repeat on a private app to separate
   "knows Rails" from "memorised campfire".
6. Optional: add the bug-fix family. Four of five campfire bugs in
   `at-file-mentions/bugs.yml` live in files that move here; plant on the
   conventional branch, then scramble that branch, so both variants carry an
   identical defect.

## Open Questions

- Whether to run the full regression suite on every non-read-only trial. It is
  on by default (`LLMX_REGRESSION_SUITE=1`) and adds roughly three minutes per
  trial across 40 trials; it does not gate success, only records it.
- Model pins: currently `claude-opus-5` and `gpt-5.6-sol`. Confirm before the
  grid, since a result cannot be attributed to a model otherwise.
