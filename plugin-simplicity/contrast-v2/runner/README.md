# Contrast v2 stage-2 preparation

This scratch harness prepares and runs independent stage-2 trials without
modifying the experiment checkout. It uses the existing `run_trial.rb`,
`harness.rb`, and `container_adapter.rb` copied into `support/` from the source
checkout.

## Assigned grid planner

The grid planner uses the existing `GridSummary` code to resolve each stage-1
cell's final path, then writes a stage-2 `grid.json` with the same identities
and prepares one catalog per cell outside the grid directory:

```sh
ruby prepare_stage2_grid.rb \
  --stage1-grid /path/to/stage1-results \
  --catalog /path/to/pristine-catalog \
  --output /path/to/stage2-results \
  --prepared-root /path/to/stage2-prepared \
  --stage-kind task_extension
```

`stage2-plan.json` lists every cell and includes a `next` command for the first
runnable one. Run one command, review its transcript and checks, then rerun the
planner with `--resume` to advance. Unstable or unavailable sources remain in
the assigned grid and are documented in `stage2-blocked/NNNN.json`. Pending
clarifications get a `resume.rb` command template and a response-file path. The
planner never writes an answer. After writing a reviewed response and running
that command, rerun it with `--resume` to prepare from the resolved final path.
Clarification commands subtract all known agent execution seconds in that
stage's `source_trial` chain from the 900-second stage budget. Stage-2 ancestry
uses `source_trial` only, so the separate `stage1_source_trial` provenance link
does not consume stage-2 time. Missing execution seconds or an exhausted budget
blocks the clarification command.

Prepare one stage-2 catalog from each retained stage-1 trial:

```sh
ruby prepare_stage2.rb \
  --source-trial /path/to/stage1-trial \
  --catalog /path/to/pristine-catalog \
  --output /path/to/stage2-prepared/cell-0001 \
  --stage-kind task_extension
```

`--stage-kind` accepts `task_extension` or `clarification`. Preparation verifies
the source status, stable workspace, both snapshot bundles, and snapshot
restoration. It restores the stage-1 final code, removes its Git metadata,
restores visible tests and support files from the pristine fixture, copies all
original hidden checks, and combines the original and follow-up checks. The
original task ID, track, and condition remain in the manifest; conditions are
copied without editing. For `task_extension`, the subject receives the specified
initial contract followed by the follow-up request under neutral headings, so
the fresh session can reproduce the required base behavior before extending it.
For `clarification`, the subject receives only the follow-up text. The manifest
records hashes for the raw follow-up, initial contract, and exact stage-2 prompt.

Run separately with the same task, agent, model, condition, and track:

```sh
ruby run_stage2.rb --prepared /path/to/stage2-prepared/cell-0001 \
  --task TASK_ID --agent codex --condition CONDITION_ID --model MODEL \
  --track natural --output /path/to/stage2-results/cell-0001 \
  --image IMAGE --auth-file AUTH_FILE
```

The wrapper enforces a 900-second stage-2 execution budget and annotates the
result metadata with `stage: 2`, `stage_kind`, stage-1 outcome/status,
`stage1_source_trial`, source final revision and bundle hash, and prompt hash.
It checks task, agent, model, condition, and track against the preparation
manifest, rejects duplicate identity flags and catalog overrides, and leaves
`source_trial` unset because the new run is an independent assignment, not a
continuation. A non-complete stage 1 with passing checks is recorded as
`unknown`, not as a pass. Keep stage-2 results in a separate grid/report
directory so their assignments are not counted as stage-1 cells.

Tests use only synthetic trials and the fake adapter:

```sh
ruby test/prepare_stage2_test.rb
```
