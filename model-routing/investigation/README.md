# Payment race investigation fixture

`model_workspace/` is the only directory to copy into each model's workspace. Keep `evaluator/` sealed until all model responses are collected. Submit the exact text in `model_workspace/PROMPT.md` with `lib/checkout.rb` and `test/checkout_test.rb` available as supplied context.

Run the reproduction with Ruby's standard library:

```sh
cd model_workspace
ruby -Itest test/checkout_test.rb
```

The test uses a Queue barrier, so both callers are guaranteed to finish the lookup before either continues. It asserts the reproduced bad outcome. It does not grade an answer and it does not prove that a proposed correction works. Score answers manually using `evaluator/rubric.md`, then consult `evaluator/answer_key.md` to adjudicate tradeoffs and assumptions.

The hidden reference check is `ruby evaluator/reference_solution_test.rb` from this directory. It demonstrates that serializing the workflow fixes the thread-level fixture. Its process-local mutex is intentionally only a test reference; it is not a Rails production recommendation for a multi-process deployment.

## Trial harness

`run_trials.rb` builds 12 sequential cells from four IDs and three repeats each, shuffled with seed `20261030`. The dry run hides model IDs and makes no model calls:

```sh
ruby run_trials.rb --models model-a,model-b,model-c,model-d --dry-run
```

Live execution uses Apple's `container` tool and the pinned Codex executable at `<tools-dir>/node_modules/.bin/codex`, matching the existing trial infrastructure. Preflight inspects the local image and compares its digest to the pilot digest, checks the CLI version from inside the image, and requires `codex login status` inside the image to report a ChatGPT login (not an API-key login). It also gates on 4 GiB free disk before the grid and before every cell. Each cell receives a fresh copy of `model_workspace/` and a distinct output directory. The task workspace copy is the only source tree mounted; `evaluator/` is never mounted. Separate per-cell result, tools, and auth mounts support result capture and the existing subscription login. `auth_runner.rb` copies only `auth.json` into a fresh container-local `CODEX_HOME` for each trial, then safely carries forward a rotated credential without replacing a nonempty token with a blank one. Full event transcripts are parsed in memory only. Each trial's original final answer is saved and hashed as `results/<blind-id>/response.md`; its model-label-redacted copy is saved separately as `blind_outputs/<blind-id>.md`. Token counts and stderr hashes are stored separately. The model-to-blind-ID key is kept in `unblinding_key.json`. Give blinded reviewers only the `blind_outputs/` files. Do not show them `response.md`, `unblinding_key.json`, per-trial run metadata, or other files under `results/`. All saved output files use owner-only permissions. The container runs with approval and sandbox bypass because the container is its isolation boundary.

This harness was not used to start live trials. The available disk is below the 4 GiB gate and the Apple container service is unavailable in this environment, so execution remains blocked. The trial parameters must be supplied using the actual four model IDs and host tools directory before creating the blinded assignment.
