# Pilot findings

Descriptive findings from the 48-cell pilot after every cell has a terminal disposition and both reviews are complete for each correct cell. Failed terminal outcomes remain in the denominators; these small exploratory results do not establish a winner or support broad claims.

## Completion and workflow

- **First-turn correct completion:** 41/48 cells reached a correct terminal result with zero continuation records; **eventual correctness:** 47/48 cells reached a correct terminal result. A checker-only recheck still counts as first turn.
- Terminal dispositions: complete=47, timeout=1.
- **Continuation records:** 40 across the grid. A checker-only recheck does not count as a continuation.
- Median cumulative agent execution time was 38.9 seconds across 48/48 cells with a recorded numeric duration. This sums execution time across continuations where present; it excludes waiting and checker runtime.
- Continuations ranged from 0 to 23 within the four-cell task/agent/condition groups. Median production changed-line counts ranged from 5.0 to 16.5 across those groups.

## Production changes by task and condition

Each row summarizes four assigned cells for one task, agent, and condition: two repeats in each of the natural and specified tracks. First-turn counts require a correct terminal result and zero continuations. Time medians use all cells with a known numeric duration (n shown); production line medians use correct terminal cells only (n shown). Production line counts are descriptive, not simplicity scores.

| Task | Agent | Recorded model | Condition | Assigned cells | Correct terminal | First-turn correct | Continuations | Median agent seconds (n known) | Median production changed lines (n correct) |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| csv_import | claude | claude-opus-5 | baseline | 4 | 4/4 | 4/4 | 0 | 48.9 (4/4) | 10.0 (4/4) |
| csv_import | claude | claude-opus-5 | ruby-plainspoken | 4 | 4/4 | 4/4 | 0 | 63.9 (4/4) | 11.0 (4/4) |
| csv_import | claude | claude-opus-5 | rubypowers | 4 | 4/4 | 4/4 | 0 | 63.8 (4/4) | 16.5 (4/4) |
| csv_import | codex | gpt-5.6-terra | baseline | 4 | 4/4 | 4/4 | 0 | 35.9 (4/4) | 11.0 (4/4) |
| csv_import | codex | gpt-5.6-terra | ruby-plainspoken | 4 | 4/4 | 4/4 | 0 | 42.8 (4/4) | 10.0 (4/4) |
| csv_import | codex | gpt-5.6-terra | rubypowers | 4 | 3/4 | 0/4 | 23 | 579.9 (4/4) | 11.0 (3/4) |
| report | claude | claude-opus-5 | baseline | 4 | 4/4 | 4/4 | 0 | 28.5 (4/4) | 5.0 (4/4) |
| report | claude | claude-opus-5 | ruby-plainspoken | 4 | 4/4 | 4/4 | 0 | 29.6 (4/4) | 5.0 (4/4) |
| report | claude | claude-opus-5 | rubypowers | 4 | 4/4 | 4/4 | 0 | 30.5 (4/4) | 5.0 (4/4) |
| report | codex | gpt-5.6-terra | baseline | 4 | 4/4 | 4/4 | 0 | 25.6 (4/4) | 6.0 (4/4) |
| report | codex | gpt-5.6-terra | ruby-plainspoken | 4 | 4/4 | 4/4 | 0 | 29.4 (4/4) | 6.0 (4/4) |
| report | codex | gpt-5.6-terra | rubypowers | 4 | 4/4 | 1/4 | 17 | 184.2 (4/4) | 6.5 (4/4) |

## Reading the results

The table separates workflow completion from production change size. Failure rows remain visible in assigned-cell and time denominators; only correct terminal cells contribute production-line medians. A condition with more continuation records can still finish with a small patch; code-line counts do not measure design quality, and cumulative agent seconds do not include human or checker waiting. No weighted score or overall winner is calculated.

The pilot uses two tasks, two repeats per task/agent/condition, and two tracks. The recorded models were Claude `claude-opus-5` and Codex `gpt-5.6-terra`; differences between agents also include their model and runtime. Treat each contrast as exploratory and task-specific.

The timeout (cell 0042) is infrastructure-confounded: its guest boot log contains kernel faults and shutdown required scoped recovery. Its code is retained, but this does not establish a model or plugin failure. The desired Codex Terra 6.1 label was rejected by the authenticated CLI; the executed model was `gpt-5.6-terra`. See [pilot limitations](../../docs/pilot-limitations.md).

## Supporting detail

- [Detailed cell comparison](comparison.md)
- [Cell and artifact index](code-index.md)
- [Automated review summary](review-findings-final/automated-review.md)
- [Workflow example: Codex RubyPowers natural cell 0014](workflow-example-0014.md)
