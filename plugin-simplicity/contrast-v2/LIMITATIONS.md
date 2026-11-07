# Reading contrast-v2 results

This is an exploratory comparison of three compact synthetic Ruby tasks, two agents, three conditions, two initial prompt tracks and two repetitions. It does not establish results for large Rails applications or a universal plugin winner.

## Requirements and checker outcomes

Natural prompts deliberately leave some requirements open. Notification's natural request does not name `flush` or define the burst boundary. Export's natural request does not prescribe the repeated-call return symbol. The specified prompts provide fuller contracts, and factual clarification answers come from those contracts. A natural-track fixed-checker failure alone does not prove that the submitted design fails the literal request. Compare natural and specified tracks separately; review natural code against its actual request. Blinded reviews include stable checker failures, with outcome labels withheld.

Before any archive-export assignment, an independent audit found four checker assertions requiring `:exported` on initial success, although even the specified prompt leaves that return value open. The assertions were removed while preserving calls and event/error/retry/idempotency checks. Original files, hashes and a nil-on-success alternative-reference proof are retained in `oracle-revision-1/`. The original manifest plus its recorded two-file hash amendment describe the executed inputs.

## Operator deviations

Initial cells 0013 and 0025 received off-protocol operator replies. Their raw metadata, code and conversations are retained. They are excluded from behavioral comparisons and marked unknown/operator error, rather than attributed to a plugin or model. Their paired follow-up assignments remain in the planned denominator but are blocked as invalid sources. Later model-facing clarification and plan-approval replies require parent review against the frozen facts.

## Fresh follow-ups

The full follow-up stage uses `runner-stage2-revision2/`. Every condition receives the specified initial behavior requirements plus the new request, with its own saved implementation as the starting production code. Original initial track remains provenance, not a difference in the follow-up wording. This context amendment was recorded before any full follow-up assignment; the two earlier follow-up smoke checks used follow-up-only context and are excluded from comparisons.

Pristine original visible tests and support files are reinstated in prepared follow-up fixtures. Initial generated tests and all other initial artifacts remain in the initial snapshots and archives. Report incremental follow-up changes separately from net final code relative to the original starting fixture. Adding initial and follow-up changed-line counts measures churn, not net final complexity.

## Models, workflow and review

The executed image pins Codex CLI 0.166.0, Claude Code 2.1.316 and Ruby 3.1.2. Codex accepted the explicit `gpt-6.1-sol` request, but its stream does not emit independent actual-model identity. Claude reports `claude-opus-5`. Older CLI failures and failed runtime builds are preflight records outside the comparison. Changes from the earlier Terra pilot also change tasks, model/CLI and protocol, so they do not isolate a model effect.

Each assignment gets 900 cumulative seconds of subject-command execution, including clarification turns. Setup, checking, teardown and evaluator waiting add wall time. Evaluator replies simulate a collaborator; their recorded counts are not real human effort measurements. Plugin inventory, startup hooks and skill invocations are observable evidence, not proof that every instruction was followed.

Two blinded Luna reviewers provide secondary architectural observations. Their ratings, disagreements and code evidence remain separate by dimension and reviewer. Review questions about uncovered edges are not newly failed acceptance checks. Lines, classes, methods and branch counts are descriptive; no weighted winner is calculated.

Stopped containers are removed only after snapshot restoration and archive/transcript verification. Host workspaces, bundles, patches, archives and conversations remain retained for inspection.
