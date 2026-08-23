---
created: 2026-08-23T05:03:43Z
branch: main
trigger: manual
restored: false
topic: convention-navigation-design
---

# Handoff: convention-navigation experiment — design written, harness not built

## Goal

Test the assumption that an agent working on a conventional Rails app spends
fewer tokens and fewer search calls than on the same app with a nonstandard,
config-wired layout, because the model already knows where things live. Test
with Claude Code and Codex first. The design is done; nothing has run.

## Current State

- `convention-navigation/README.md` written: full experiment design (question,
  conditions, scramble rules, task families, metrics, pre-registered decision
  rule, threats, planned layout).
- Root `README.md` table updated with the new experiment row
  ("design written, not yet run").
- No scripts, prompts, tasks.yml, or apps.yml exist yet.
- Changes are uncommitted, on `main`. Repo convention is to branch
  (`experiment/...` or `fix/...`) and merge via PR.

## Key Decisions

- One app, two layouts — not Rails vs another framework. Comparing different
  apps confounds language, size, and familiarity; a behavior-preserving
  "scrambled" variant of one app isolates path predictability.
- Scramble moves files and adds config wiring but renames nothing — keeps
  grep-by-identifier equally powerful in both variants, so differences are
  attributable to path knowledge alone.
- Breaking the test-path mirror is part of the treatment — mirroring is itself
  a Rails convention (at-file-mentions showed agents exploit it).
- Third condition `scrambled-mapped` (scrambled + AGENTS.md/CLAUDE.md map) —
  answers the practical follow-up: does documentation buy the advantage back,
  and what does carrying it cost per request.
- Task prompts must contain zero identifiers — an identifier is a "grep
  coupon" that erases the variable; render_prompts.rb should fail mechanically
  if a prompt string greps too narrowly. Cross-layer feature tasks
  (migration+model+controller+view) are the load-bearing family; single-symbol
  lookups are where grep wins.
- 5 repeats, not 3 — this repo has retracted claims built on 3 runs
  (see startup-context fix commits).
- Campfire for phase 1 (container image already exists), a private app
  (postcraftstudio or bookmarks) for phase 2 to separate "memorized campfire"
  from "knows Rails".
- Reuse at-file-mentions infrastructure: containers, plant.rb, transcript
  parsers, exact Mann-Whitney in metrics.rb, sanitize.rb pattern.
- `bin/rails routes` etc. stay allowed and counted under bash calls — if
  runtime introspection substitutes for conventions, that is the finding.

## Modified Files

- `README.md` (modified — new experiment table row)
- `convention-navigation/README.md` (new)

## Failed Approaches

- None — design-only session, nothing executed.

## Files to Read

- `convention-navigation/README.md` — the full design; source of truth
- `at-file-mentions/README.md` — infrastructure to reuse and the
  "grep reached the defect in 1 call" observation that shaped the design
- `startup-context/README.md` — per-CLI token accounting rules (Claude sums
  three buckets; Codex includes cache in input) and container rationale
- `at-file-mentions/scripts/` — parse_transcript.rb, metrics.rb, sanitize.rb,
  run_grid.rb to adapt

## Next Steps

1. Commit the design on a branch (e.g. `experiment/convention-navigation-design`), PR to main.
2. Build `scripts/scramble.rb` + `scripts/scramble_check.rb` (suite green on
   both variants, moved files content-equal modulo wiring whitelist, no
   renames) — the only genuinely new machinery.
3. Write `tasks.yml` (4 pilot tasks: 1 locate, 1 planted bug, 1 cross-layer
   feature, 1 test-writing) with scripted acceptance checks.
4. `render_prompts.rb` with the grep-coupon check.
5. Adapt runner/parser/metrics/sanitize from at-file-mentions; add per-class
   tool-call counts and the zero-search-navigation flag; ensure target files
   land in meta.json (known silent-failure mode).
6. Run phase 1: 2 agents × 2 conditions × 4 tasks × 5 repeats = 80 trials.

## Open Questions

- Which app gets scrambled first — campfire assumed for image reuse, but
  confirm the user is fine with the memorization caveat for the pilot.
- Exact scramble recipe depth (how aggressive the config indirection gets)
  is described in rules, not yet specified file-by-file.
- Model pins for the run (repo precedent: sonnet for Claude, gpt-5.6-sol for
  Codex) — confirm at harness-build time.
