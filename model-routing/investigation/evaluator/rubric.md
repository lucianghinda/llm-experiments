# Blinded human scoring rubric

Score each response from 0 to 4 on each dimension, using the anchors below. Total: 20. Record a short quote or paraphrase of the evidence for every nonzero score. Do not infer unstated correctness from confident phrasing. The evaluator should not see model identity until scoring is complete.

| Dimension | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| Root cause | Misses the defect | Vague race/concurrency mention | Identifies check-then-act gap | Correctly maps lookup, gateway, insert ordering | Also distinguishes statement-level synchronization from workflow atomicity |
| Execution evidence | No timeline | Generic two-request claim | Plausible interleaving | Concrete timeline where both observe absence before calls | Timeline explains resulting duplicate external effect and rows |
| Correction | None or incorrect | In-process lock only | Mentions transaction/unique key incompletely | Database uniqueness plus conflict recovery or durable per-key serialization | Correct multi-process-safe design, uniqueness, conflict recovery, and avoids network-in-transaction trap |
| Retry / failure semantics | Ignores retries | Says “retry safely” | Stable key, no explanation | Covers ambiguous timeout/retry and same logical key | Explicitly bounds exactly-once guarantees; requires provider contract or reconciliation/outbox strategy |
| Regression test / tradeoffs | Neither | Generic test or tradeoff | One specific but weak check | Concurrent same-order test with observable assertion and a relevant limitation | Tests duplicate prevention and ambiguous retry recovery, with tradeoff/limitation grounded in evidence |

## Decision guidance

- 17–20: strong diagnosis and production reasoning.
- 13–16: mostly correct, one material omission.
- 8–12: partial; likely spots race but solution is incomplete.
- 0–7: misses core behavior or proposes unsafe fix.

This is a rubric for blinded human assessment, not an automatic pass/fail test. Preserve raw responses and score evidence before unblinding model labels. If an answer proposes a different architecture, score its guarantees and assumptions against the answer key rather than requiring specific wording.
