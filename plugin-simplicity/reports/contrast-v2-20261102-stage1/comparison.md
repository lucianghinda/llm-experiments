# Assigned-cell comparison

As of 2026-11-02T19:41:44Z (UTC): **In progress**. Assigned cells: 72; dispositions: complete=38, task_failure=10, awaiting_review=1, unstarted=23.

Descriptive counts only; they are not quality grades or simplicity scores. Correctness is based on the recorded checker/restoration result. Review grading is pending. This grid contains 72 assigned cells across 3 tasks and 2 assigned repeats per condition; these small samples do not establish a winner.

Infrastructure/checker workflow changed after five assignments. The initial Codex kernel crash happened during smoke validation, outside this 48-cell grid; its incident record is excluded from these pilot cells. Read run incident notes before combining cells across the workflow transition.

## Grouped cells

| Agent | Task | Track | Condition | Correct / assigned | Completed | Status counts | Median production changed lines (correct only) | Median method delta | Median class delta | Median branch delta | Median recorded wall seconds (correct/complete) | Median cumulative agent seconds (completed) | Median known cumulative seconds (all outcomes) |
|---|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|
| claude | archive_export | natural | baseline | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| claude | archive_export | natural | ruby-plainspoken | 0 / 2 | 0 | awaiting_review=1, unstarted=1 | unknown | unknown | unknown | unknown | unknown | unknown | 113.72396299988031 |
| claude | archive_export | natural | rubypowers | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| claude | archive_export | specified | baseline | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| claude | archive_export | specified | ruby-plainspoken | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| claude | archive_export | specified | rubypowers | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| claude | notification_digest | natural | baseline | 1 / 2 | 1 | complete=1, task_failure=1 | 38 | 7 | 2 | 1 | 213.0 | 128.92192299989983 | 96.94166849995963 |
| claude | notification_digest | natural | ruby-plainspoken | 0 / 2 | 0 | task_failure=2 | unknown | unknown | unknown | unknown | unknown | unknown | 76.94361949991435 |
| claude | notification_digest | natural | rubypowers | 0 / 2 | 0 | task_failure=2 | unknown | unknown | unknown | unknown | unknown | unknown | 82.75675450009294 |
| claude | notification_digest | specified | baseline | 2 / 2 | 2 | complete=2 | 12.5 | 1.0 | 0.0 | 0.0 | 60.0 | 25.554834000067785 | 25.554834000067785 |
| claude | notification_digest | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 11.5 | 1.0 | 0.0 | 0.0 | 83.5 | 45.050681499997154 | 45.050681499997154 |
| claude | notification_digest | specified | rubypowers | 2 / 2 | 2 | complete=2 | 20.0 | 4.5 | 1.0 | 1.0 | 82.0 | 42.397962499875575 | 42.397962499875575 |
| claude | regional_policy | natural | baseline | 2 / 2 | 2 | complete=2 | 14.5 | 0.5 | 0.0 | -0.5 | 177.0 | 97.84967050002888 | 97.84967050002888 |
| claude | regional_policy | natural | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 207.0 | 107.72437499975786 | 107.72437499975786 |
| claude | regional_policy | natural | rubypowers | 2 / 2 | 2 | complete=2 | 17.5 | 0.5 | 0.0 | -1.0 | 167.0 | 102.41970099997707 | 102.41970099997707 |
| claude | regional_policy | specified | baseline | 2 / 2 | 2 | complete=2 | 48.0 | 1.5 | 0.0 | -3.5 | 71.0 | 52.987280999775976 | 52.987280999775976 |
| claude | regional_policy | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 92.0 | 56.73216299992055 | 56.73216299992055 |
| claude | regional_policy | specified | rubypowers | 2 / 2 | 2 | complete=2 | 7.5 | 0.0 | 0.0 | 0.0 | 83.0 | 41.08420299994759 | 41.08420299994759 |
| codex | archive_export | natural | baseline | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| codex | archive_export | natural | ruby-plainspoken | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| codex | archive_export | natural | rubypowers | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| codex | archive_export | specified | baseline | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| codex | archive_export | specified | ruby-plainspoken | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| codex | archive_export | specified | rubypowers | 0 / 2 | 0 | unstarted=2 | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| codex | notification_digest | natural | baseline | 0 / 2 | 0 | task_failure=2 | unknown | unknown | unknown | unknown | unknown | unknown | 38.47258750000037 |
| codex | notification_digest | natural | ruby-plainspoken | 0 / 2 | 0 | task_failure=2 | unknown | unknown | unknown | unknown | unknown | unknown | 34.087311500217766 |
| codex | notification_digest | natural | rubypowers | 1 / 2 | 1 | complete=1, task_failure=1 | 11 | 1 | 0 | 0 | 149.0 | 61.238584000151604 | 57.26216099993326 |
| codex | notification_digest | specified | baseline | 2 / 2 | 2 | complete=2 | 11.0 | 1.0 | 0.0 | 0.0 | 88.0 | 27.516390499891713 | 27.516390499891713 |
| codex | notification_digest | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 11.0 | 1.0 | 0.0 | 0.0 | 84.5 | 26.31199250021018 | 26.31199250021018 |
| codex | notification_digest | specified | rubypowers | 2 / 2 | 2 | complete=2 | 11.0 | 1.0 | 0.0 | 0.0 | 103.5 | 37.61313849990256 | 37.61313849990256 |
| codex | regional_policy | natural | baseline | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 125.0 | 38.08168249996379 | 38.08168249996379 |
| codex | regional_policy | natural | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 144.5 | 38.30676750023849 | 38.30676750023849 |
| codex | regional_policy | natural | rubypowers | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 156.5 | 46.774514499818906 | 46.774514499818906 |
| codex | regional_policy | specified | baseline | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 75.5 | 21.96623899997212 | 21.96623899997212 |
| codex | regional_policy | specified | ruby-plainspoken | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 131.0 | 27.93662099982612 | 27.93662099982612 |
| codex | regional_policy | specified | rubypowers | 2 / 2 | 2 | complete=2 | 4.0 | 0.0 | 0.0 | 0.0 | 124.5 | 27.63428199966438 | 27.63428199966438 |

`Correct / assigned` retains the assigned denominator. Production changed lines and structural medians use only checker-passing, restoration-verified solutions. Structural deltas are method definitions, classes, and branch nodes, respectively. Unknown measurements remain unknown.

Recorded wall time is reported only for correct, completed cells when available. It spans the first recorded attempt start through the final attempt finish, so it includes elapsed gaps and evaluator/checker waiting; this pilot cannot attribute that time to the plugin or agent. Missing wall-time records remain unknown.

## Cumulative execution-time medians

Completed-only median: 41.03297350020148 seconds (n=38, unknown=0). All-outcome median over cells with any recorded agent duration: 43.72625999990851 seconds (n=49, unknown=23). The second population includes known partial chains for failures and unfinished cells.

Agent execution durations above exclude checker runtime, waiting, human review, and unrecorded work. No review grade or quality winner is inferred.
