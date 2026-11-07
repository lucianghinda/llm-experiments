# Contrasting Ruby cases

Three stdlib-only evaluation fixtures, prepared without running a live model. Copy each `fixtures/ID` tree into an isolated workspace. Run `ruby test/test_app.rb` there for existing behavior, then run `ruby /path/to/case-root/checks/ID.rb` with that workspace as the current directory. Follow-up checks run after the follow-up prompt. Hidden checks only inspect public behavior.

- `notification_digest`: a layered notification path already suppresses system events and formats user messages. The added feature groups a batch by actor and reports the number of messages delivered at flush.
- `regional_policy`: checkout and delivery estimates have similar but distinct regional rules. Both need the southern free-shipping threshold update; a later checkout-only handling exception preserves their difference.
- `archive_export`: export crosses a writer publication boundary. The writer's `publish(entries)` operation stages visibility atomically and can fail at the header, row, or finish phase. Failed publication remains retryable; completion is tracked independently for each writer passed to the exporter.

`references/ID/app.rb` is the stage-one reference; where follow-up behavior differs, `references/ID/followup_app.rb` contains that later implementation. `ruby validate.rb` checks starter baseline tests, starter rejection of acceptance and follow-up checks, and reference results at both stages. The same matrix is retained in `validation-results.json`.

## Comparing conditions

This is a separate catalog; the completed pilot inputs and results remain frozen. The runnable task contracts are in prompts/; DESIGN.md discusses broader future extensions as well. Live execution is now running after six initial smoke arms and two fresh-session smoke extensions passed. The cases offer opportunities for differences, without guaranteeing separation or a winner.

Run all three conditions against identical snapshots. Record first-stage correctness, follow-up correctness, operator responses, execution time, and blinded architecture review. Inspect whether changes preserve required boundaries, remove or add unnecessary concepts, and localize the second change. Lines/classes alone are not a score. Reference implementations demonstrate feasibility and are not the only accepted architecture; they remain outside the subject fixtures.

Follow-up stages must rerun existing and stage-one checks as well as the follow-up check. Freeze the session policy before model runs: keep condition assignment and record whether the follow-up uses continued or fresh context. The existing grid runner executes initial stages; its followup metadata does not automatically schedule second-stage runs.

Validate locally: `ruby validate.rb`.

Preview the initial grid without model calls from the parent experiment directory:

```sh
ruby scripts/run_grid.rb --catalog contrast-v2 --output /tmp/contrast-preview --tasks notification_digest,regional_policy,archive_export --claude-model claude-opus-5 --codex-model gpt-5.6-terra --dry-run
```

## Live comparison: 2026-11-02

Luna helpers coordinate the runs. Subjects are Codex with an explicit accepted `gpt-6.1-sol` request (CLI 0.166.0; actual-model stream field unavailable) and Claude `claude-opus-5` (CLI 2.1.316). The initial grid has 72 assignments; the paired fresh-session follow-up grid retains 72 assignments. Each assignment has a cumulative 900-second agent-execution budget. All source snapshots, binary patches, worktree archives and transcripts are retained.

Fresh follow-up sessions receive the initial specified behavior requirements plus the new request, equally across conditions. Their production baseline is their own saved initial implementation, with pristine visible tests reinstated. Initial prompt track remains provenance. The versioned stage-2 context and control amendments are recorded before the full follow-up grid.

[In-progress initial code index](../reports/contrast-v2-20261102-stage1/code-index.md) · [Frozen protocol](../results-raw/contrast-v2-20261102-protocol/manifest.json)

This is exploratory. Natural notification requests leave the burst API unspecified, so fixed-checker failures alone do not establish poor implementations; natural and specified tracks must be read separately. A checker amendment removed unstated archive-success return requirements before any export assignment started. Cell 0013 is excluded for a controller clarification error, and its paired follow-up remains assigned but blocked; raw code and the exact deviation record remain retained. No plugin winner is declared while execution is in progress.
