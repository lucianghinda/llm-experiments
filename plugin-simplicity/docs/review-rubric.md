# Blinded code review rubric

Score each dimension independently from 1 to 5. These four ratings are the primary assessment; do not collapse them into a winner score. Cite specific code constructs in each rationale. Judge the production code, not patch size by itself.

## Dimensions

### Concepts

How few distinct concepts does the change ask a maintainer to understand while still expressing the required behavior?

- **1** — Many unnecessary ideas, special cases, state, or abstractions obscure the behavior.
- **2** — Noticeable conceptual overhead or duplication.
- **3** — Understandable, with some avoidable machinery.
- **4** — A small set of clear, purposeful concepts.
- **5** — The behavior is expressed with only the concepts it needs.

### Justified indirection and boundaries

Are extracted methods, objects, layers, and boundaries justified by a real contract, behavior, invariant, or external boundary?

- **1** — Indirection hides behavior and has no clear ownership or contract.
- **2** — Several boundaries add hops without a clear benefit.
- **3** — Mostly appropriate, though some indirection is questionable.
- **4** — Boundaries make ownership or change safer and clearer.
- **5** — Every abstraction earns its place and keeps responsibilities easy to follow.

### Cohesion and fit

Does the change keep related behavior together and follow the established domain language and structure visible in the packet?

- **1** — Responsibilities are scattered or conflict with surrounding design.
- **2** — Several pieces are split or inconsistent without a clear reason.
- **3** — Adequate cohesion and fit, with some friction.
- **4** — Related behavior is grouped and consistent with nearby code.
- **5** — The change fits naturally and keeps each responsibility coherent.

### Interfaces and error clarity

Are inputs, outputs, and failure behavior clear at the relevant boundaries?

- **1** — Contracts or failure modes are hidden, ambiguous, or surprising.
- **2** — Important interface or error behavior needs inference.
- **3** — Mostly clear, with some unspecified or indirect behavior.
- **4** — Interfaces and failures are clear and predictable.
- **5** — Contracts are explicit, narrow, and easy for callers to use correctly.

## Review procedure

1. Read the neutral behavior contract if one is supplied, then baseline, final production code, and patch.
2. Score the four dimensions independently before comparing packets.
3. Cite specific code evidence for each score. If two packets seem equivalent, give them the same score.
4. Do not infer or investigate the agent, model, plugin, condition, prompt, workflow, or trial identity. Do not use transcripts, tests, docs, metadata, or outcome tables when judging these dimensions.
5. Record correctness concerns separately. Only final snapshots with passing recorded acceptance checks and restoration validation receive score packets; baseline is the starting code and is not expected to satisfy the requested behavior.

## Building packets

```sh
ruby scripts/review_packets.rb RESULTS_ROOT OUTPUT_DIR --seed 42
```

Packet IDs and ordering are deterministic for a given input order and seed. The builder refuses to overwrite an existing output directory. It creates `packets/`, a mode-0600 `private-key.json`, and a mode-0600 `outcomes.md`. Share only `packets/` with reviewers; keep the key and outcome table private. The outcome table retains failed and excluded attempts with their validation reason.

A neutral behavior contract can be supplied as a JSON object mapping task IDs to plain requirement text. The contract must not mention the assigned condition, agent, model, plugin, or workflow. Without one, packets say that context is limited to the code snapshots and patch.

```sh
ruby scripts/review_packets.rb RESULTS_ROOT OUTPUT_DIR --seed 42 --contracts task-contracts.json
```

When a results root has continuation records, supply exactly one validated final-trial path per grid cell. The path list may be newline-separated or a JSON array. A continuation's `source_trial` chain identifies its original grid cell, and the packet compares that cell's original baseline against the selected final snapshot.

```sh
ruby scripts/review_packets.rb RESULTS_ROOT OUTPUT_DIR --seed 42 --final-trials finals.txt --contracts task-contracts.json
```

The builder includes changed `.rb`, `.erb`, and `.rake` production files only. It excludes tests, documentation trees, vendored code, and `.agents`, `.claude`, `.codex`, and `.omx` workflow trees. Prompts, transcripts, docs, tests, and trial metadata are never copied into blinded packets. Correctness checks and restoration must pass before a trial can produce a packet. If no production code changed, the attempt remains in the private outcome table with that reason and gets no score packet.

Preserve the seed and private mapping with study records so ratings can later be joined to trial metadata. Two independent automated reviewers apply this rubric to the pilot as secondary evidence. Their original ratings and disagreements are retained; human review remains available. Packet scores do not select a winner automatically.
