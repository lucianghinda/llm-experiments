# Assigned-cell comparison

As of 2026-11-02T13:52:09Z (UTC): **All assigned cells have a recorded terminal disposition**. Assigned cells: 48; dispositions: complete=47, timeout=1.

Descriptive counts only; they are not quality grades or simplicity scores. Correctness is based on the recorded checker/restoration result. Review grading is pending. This grid contains 48 assigned cells across 2 tasks and 2 assigned repeats per condition; these small samples do not establish a winner.

Infrastructure/checker workflow changed after five assignments. The initial Codex kernel crash happened during smoke validation, outside this 48-cell grid; its incident record is excluded from these pilot cells. Read run incident notes before combining cells across the workflow transition.

## Grouped cells

| Agent | Task | Track | Condition | Correct / assigned | Completed | Status counts | Median production changed lines (correct only) | Median method delta | Median class delta | Median branch delta | Median recorded wall seconds (correct/complete) | Median cumulative agent seconds (completed) | Median known cumulative seconds (all outcomes) |
|---|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|
| claude | csv_import | natural | baseline | 2 / 2 | 2 | complete=2 | 10.0 | 0.0 | 0.0 | 0.0 | 69.0 | 45.90311100007966 | 45.90311100007966 |
| claude | csv_import | natural | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 11.0 | 0.0 | 0.0 | 0.0 | 144.5 | 67.09949199995026 | 67.09949199995026 |
| claude | csv_import | natural | rubypowers | 2 / 2 | 2 | complete=2 | 13.0 | 0.5 | 0.0 | 0.0 | 147.0 | 78.50153249991126 | 78.50153249991126 |
| claude | csv_import | specified | baseline | 2 / 2 | 2 | complete=2 | 11.0 | 0.0 | 0.0 | 0.0 | 76.0 | 48.85247949999757 | 48.85247949999757 |
| claude | csv_import | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 12.0 | 0.0 | 0.0 | 0.5 | 144.0 | 56.97873350000009 | 56.97873350000009 |
| claude | csv_import | specified | rubypowers | 2 / 2 | 2 | complete=2 | 18.0 | 1.0 | 0.0 | 0.5 | 152.5 | 50.13697749981657 | 50.13697749981657 |
| claude | report | natural | baseline | 2 / 2 | 2 | complete=2 | 5.0 | 0.0 | 0.0 | 1.0 | 53.0 | 34.93450800003484 | 34.93450800003484 |
| claude | report | natural | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 5.0 | 0.0 | 0.0 | 1.0 | 144.5 | 33.5315610000398 | 33.5315610000398 |
| claude | report | natural | rubypowers | 2 / 2 | 2 | complete=2 | 5.0 | 0.0 | 0.0 | 1.0 | 151.5 | 31.0261500000488 | 31.0261500000488 |
| claude | report | specified | baseline | 2 / 2 | 2 | complete=2 | 5.0 | 0.0 | 0.0 | 1.0 | 45.5 | 22.564968000166118 | 22.564968000166118 |
| claude | report | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 5.0 | 0.0 | 0.0 | 1.0 | 141.0 | 26.560900500044227 | 26.560900500044227 |
| claude | report | specified | rubypowers | 2 / 2 | 2 | complete=2 | 5.0 | 0.0 | 0.0 | 1.0 | 143.5 | 28.35799100017175 | 28.35799100017175 |
| codex | csv_import | natural | baseline | 2 / 2 | 2 | complete=2 | 11.0 | 0.0 | 0.0 | 0.0 | 51.0 | 28.557025499874726 | 28.557025499874726 |
| codex | csv_import | natural | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 9.0 | 0.0 | 0.0 | 0.0 | 147.5 | 42.78288049995899 | 42.78288049995899 |
| codex | csv_import | natural | rubypowers | 1 / 2 | 1 | complete=1, timeout=1 | 14 | 0 | 0 | 0 | 610.0 | 298.56603000080213 | 598.8271425003186 |
| codex | csv_import | specified | baseline | 2 / 2 | 2 | complete=2 | 11.0 | 0.0 | 0.0 | 0.0 | 62.0 | 41.49599099997431 | 41.49599099997431 |
| codex | csv_import | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 11.0 | 0.0 | 0.0 | 0.0 | 145.0 | 36.56554399989545 | 36.56554399989545 |
| codex | csv_import | specified | rubypowers | 2 / 2 | 2 | complete=2 | 10.0 | 0.0 | 0.0 | 0.0 | 902.0 | 579.9202305006329 | 579.9202305006329 |
| codex | report | natural | baseline | 2 / 2 | 2 | complete=2 | 6.5 | 0.0 | 0.0 | 1.0 | 45.5 | 25.812443000264466 | 25.812443000264466 |
| codex | report | natural | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 6.0 | 0.0 | 0.0 | 1.0 | 141.0 | 24.214196000015363 | 24.214196000015363 |
| codex | report | natural | rubypowers | 2 / 2 | 2 | complete=2 | 7.0 | 0.0 | 0.0 | 1.0 | 673.0 | 226.68216449930333 | 226.68216449930333 |
| codex | report | specified | baseline | 2 / 2 | 2 | complete=2 | 6.0 | 0.0 | 0.0 | 1.0 | 42.0 | 21.793235500110313 | 21.793235500110313 |
| codex | report | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 6.0 | 0.0 | 0.0 | 1.0 | 149.0 | 39.01650750008412 | 39.01650750008412 |
| codex | report | specified | rubypowers | 2 / 2 | 2 | complete=2 | 6.0 | 0.0 | 0.0 | 1.0 | 338.5 | 139.95712650031783 | 139.95712650031783 |

`Correct / assigned` retains the assigned denominator. Production changed lines and structural medians use only checker-passing, restoration-verified solutions. Structural deltas are method definitions, classes, and branch nodes, respectively. Unknown measurements remain unknown.

Recorded wall time is reported only for correct, completed cells when available. It spans the first recorded attempt start through the final attempt finish, so it includes elapsed gaps and evaluator/checker waiting; this pilot cannot attribute that time to the plugin or agent. Missing wall-time records remain unknown.

## Cumulative execution-time medians

Completed-only median: 37.16803500009701 seconds (n=47, unknown=0). All-outcome median over cells with any recorded agent duration: 38.9463649999816 seconds (n=48, unknown=0). The second population includes known partial chains for failures and unfinished cells.

Agent execution durations above exclude checker runtime, waiting, human review, and unrecorded work. No review grade or quality winner is inferred.
