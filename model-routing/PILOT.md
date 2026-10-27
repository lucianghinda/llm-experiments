# Convention navigation model pilot

The pilot compares four Codex models over the four existing tasks, using one
conventional-layout run for each task/model pair. It shuffles the 16 cells from
a recorded seed and runs sequentially. The labels preserve the task definitions:
two locate prompts are read-only, while the cross-layer feature and test-addition
prompts permit repository changes.

Preview without filesystem changes:

```sh
ruby model-routing/pilot.rb --dry-run --seed 20261027
```

Prepare a reviewable local plan, including prompt copies and `status.json`:

```sh
ruby model-routing/pilot.rb --prepare-plan --seed 20261027
```

For a live run, authenticate through the existing subscription login flow, then
provide the directory containing `node_modules/.bin/codex`:

```sh
ruby containers/scripts/auth_setup.rb --agent codex
ruby model-routing/pilot.rb --run --auth=subscription --tools-dir "$CODEX_TOOLS_DIR" --seed 20261027
```

The pilot mounts the authenticated Codex home using `Kit.run_args`; the
`--auth=subscription` flag is mandatory and recorded in status metadata. It does
not call an API key path or claim a dollar hard cap. Trial outputs, copied
prompts, and status are contained under `model-routing/runs/`.

## Usage and API-equivalent estimates

`status.json` records subscription-run usage tokens from Codex `turn.completed`
transcript events. Codex `input_tokens` includes cached input; cached tokens are
also reported as a subset and must not be added to the total. It records
API-equivalent estimates in a separate field and
only calculates them when an explicit rates file is supplied. An example rates
entry for every model must include:

```json
{
  "gpt-6-luna": {
    "input_per_million": null,
    "cached_input_per_million": null,
    "output_per_million": null,
    "source": "pricing reference URL or document",
    "as_of": "YYYY-MM-DD"
  }
}
```

Replace the nulls with verified rates before passing `--api-rates`. Missing or incomplete rates produce a null
estimate. These API-equivalent values are analytical estimates, not subscription
charges, and do not limit subscription usage.

The runner and runner-in-container are isolated copies under `scripts/`; the
upstream convention-navigation harness remains untouched by pilot-specific
changes. The container tools mount is passed with `--tools-dir`, not a fixed host
path.
