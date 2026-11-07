# Plugin simplicity pilot

This is an exploratory live pilot, not a paid study. The Apple container adapter, native plugin installation, credential isolation, checker isolation, and explicit continuation flow have now been exercised against real runtimes. The smoke path passed for both supported agents and the continuation path passed for Claude and Codex. The initial Codex kernel crash occurred during smoke validation, outside the 48-cell pilot; its incident record is excluded from pilot assignments.

The 48-cell pilot in `results-raw/pilot-20261102` has terminal records for all 48 assigned cells as of 2026-11-02T13:54:00Z UTC. GridSummary disposition counts: complete=47, timeout=1. GridSummary complete with checker/restoration evidence: 47/48. All six smoke checks passed; Claude and Codex continuation checks passed. Both automated blind-review batches are complete. Human inspection of retained code is available; no plugin or condition is declared a winner. Cell 0042 remains recorded as a timeout; see the incident note for its infrastructure-confounded context.

Reports: [comparison](reports/pilot-20261102/comparison.md), [code index](reports/pilot-20261102/code-index.md), [final findings](reports/pilot-20261102/FINDINGS.md), [final review](reports/pilot-20261102/review-findings-final/automated-review.md), [pilot limitations](docs/pilot-limitations.md). Terra 6.1 was the desired Codex model label, but the authenticated CLI rejected it; the run used `gpt-5.6-terra` accepted by Codex CLI `0.147.0`. This CLI model is distinct from the native orchestration label. The requested Claude alias was `claude-opus-5`; CLI `2.1.233` resolved it to `claude-opus-5`. See the run artifacts and incident records before interpreting any outcome.

The catalog contains six tasks. The default pilot grid uses `report` and `csv_import`, both tracks, three conditions, two agents, and two repetitions: 48 cells. Supply explicit model names. A dry run reads the catalog and prints the randomized plan without writing output or calling a model:

```sh
ruby scripts/run_grid.rb --catalog . --output /tmp/pilot-results --claude-model MODEL --codex-model MODEL --dry-run
```

Use `--tasks report,identifiers` to select a different set and `--seed N` to reproduce order. Live execution additionally requires an explicit `--image`, `--claude-auth-file` and `--codex-auth-file`. The image must run as a non-root agent user and contain Ruby, Git, both agent CLIs, the fixture's dependencies and a shell; build and validate it separately using the sibling `containers/` kit. The grid stops on a non-successful or review-pending cell; its `grid.json` retains the remaining plan. It does not resume the grid automatically.

For a single live trial, provide `--task`, `--agent`, `--condition`, `--track`, `--model`, `--catalog`, `--output`, `--image` and `--auth-file` to `scripts/run_trial.rb`. For example:

```sh
ruby scripts/run_trial.rb --task report --agent codex --condition baseline --track specified --model MODEL --catalog . --output /tmp/pilot-one --image IMAGE --auth-file /path/to/auth.json
```

The stopped subject container retains its seeded credential until explicitly removed. Inspect a container with `container inspect CONTAINER_NAME`. After reviewing and preserving a trial, cleanup checks the snapshot and stopped state before removing only the container:

```sh
ruby scripts/cleanup.rb --reviewed-complete /path/to/trial
```

The adapter starts a fresh Apple container, mounts a private fixture copy, seeds one credential file into private configuration, installs the selected plugin through its native local marketplace, records inventory, runs the agent and stops the container. It retains the container and workspace. Checks run after the stopped subject, in a separate checker container against a restored copy; hidden checks are only mounted in that checker. Do not interpret an agent exit code as task correctness; inspect `checks.json`, `meta.json`, and the code.

Each attempt retains its workspace, prompt, transcript, stderr, metadata, baseline and final Git bundles, binary patch, and check results where available. Restoration checks out both snapshots and applies the patch to the baseline before comparing trees. If a container cannot be stopped, the workspace is retained and snapshotting is refused until it is stable. Artifacts are raw and may contain sensitive information; no sanitization is implemented.

```sh
ruby scripts/index.rb /path/to/results
ruby scripts/report.rb /path/to/results
ruby scripts/restore.rb /path/to/trial /tmp/restored-final
ruby scripts/restore.rb /path/to/trial /tmp/restored-baseline baseline
ruby scripts/structure.rb /path/to/baseline /path/to/final
ruby scripts/structure.rb --bundles /path/to/baseline.bundle /path/to/final.bundle
ruby scripts/review_packets.rb /path/to/results /path/to/review-packets --seed N
```

`review_packets.rb` accepts `--final-trials FILE` to supply one validated final trial path per grid cell as a JSON array or newline list. These tools prepare data for review; they do not grade outcomes automatically.

The Campfire task readiness evidence and remaining gate are in [docs/campfire-validation.md](docs/campfire-validation.md). The task catalog has intentionally not been changed during the pilot.

For harness verification only, `run_trial.rb` accepts `--fake-command` with the path of an executable. It runs on the host, in a copied fixture, and receives the prompt on stdin. It is not isolated; never use it for real agents or untrusted code. Test the harness with a current Ruby:

```sh
ruby test/harness_test.rb
ruby test/container_adapter_test.rb
ruby test/resume_test.rb
```

A live run records `awaiting_review` when checks do not establish completion. Review the transcript and supply an explicit answer file and the agent session ID; neither an answer nor an approval is invented by the harness:

```sh
ruby scripts/resume.rb --trial /path/to/trial --session-id SESSION_ID --response-file /path/to/answer.txt --output /path/to/continuation
```

Each continuation keeps its own response, transcript, metadata and snapshot. Checks run against the restored snapshot after each continuation. Do not count `awaiting_review` as a completed result.
