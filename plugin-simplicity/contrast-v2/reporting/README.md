# Contrast v2 report proposal (staged)

This proposal is isolated under `/private/tmp/contrast-v2-reporting`. It reads both result roots and delegates cell/check/production-diff interpretation to the existing `GridSummary`; it writes only report files to the caller-provided output directory. Nothing here is installed in the experiment repo or attached to the live runtime.

```sh
ruby contrast_v2_report.rb \
  --stage1 /path/to/results-raw/contrast-v2-20261102-stage1 \
  --stage2 /path/to/results-raw/contrast-v2-20261102-stage2 \
  --grid-summary /path/to/plugin-simplicity/scripts/grid_summary.rb \
  --output /path/to/report-output
```

The tool emits `summary.json` and `report.md`, including both assigned denominators, initial and cumulative-stage correctness, follow-up-specific check results, both conditional follow-up denominators, elapsed wall spans, recorded agent execution time, a stage path index, and every current or historical blocked sidecar. It labels stage-2 code metrics as incremental from the prepared stage-1 final baseline. Unknown values remain unknown. It never opens blinded-review keys.

Final state is gated on exactly 72 assigned cells at each stage, one unique identity per assignment, no identity/provenance join errors, no pending cell, and one correctly matched current blocked sidecar for each stage-2 blocked disposition (with no extra or duplicate blocked sidecars). Old sidecars are historical when a stage-2 trial record exists. Partial roots are reported as `in_progress` without treating missing records as failures. Output is refused inside either grid, frozen inputs, or source, and existing primary report files are never overwritten.

## Review contracts and packet batching

Use `contracts-stage1-natural.json` for stage-1 natural-track packets and `contracts-stage1-specified.json` for stage-1 specified-track packets. They follow their respective frozen prompts. In particular, the natural notification prompt does not specify a flush API or burst boundary implementation, so its review contract does not add those requirements.

Batch stage-1 blinded packet creation by track. Review packet contracts are keyed only by task ID, so one invocation over both tracks cannot safely choose between natural and specified wording. Keep the two output sets and their private mappings separate, and only combine blinded packets after the task-keyed contract has been selected for each track.

For fresh stage-2 subjects, use `contracts-stage2-followup-review.json` as the reviewer contract. It says the baseline is the code supplied at the beginning of the task and includes only the follow-up request that was actually presented. Do not use it to imply the initial specified prompt was repeated.

`contracts-stage2-cumulative-checker.json` is a separate cumulative behavior contract for interpreting the combined initial and follow-up acceptance checks. It is not the stage-2 blinded-review contract. Keep both files labeled by purpose when preparing materials, and keep the review packet builder's private mapping with the study owner. All requirements were copied from frozen prompts or the staged cumulative contract; no oracle amendments were used.

Synthetic tests exercise partial runs, blocked-sidecar accounting, assignment/provenance mismatch, and the explicit incremental stage-2 production metric label.

Stage-2 context amendment (before the full follow-up grid): runner-stage2-revision2 supplies the specified initial behavior contract plus the new request. contracts-stage2-followup-review.json now contains that exact combined subject prompt. Earlier follow-up-only smoke context is superseded for the full grid; original initial assignments are unchanged.
