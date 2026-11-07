# Second-wave contrast design

## Aim

Compare baseline, RubyPowers, and ruby-plainspoken as aids to sound Ruby work, not as a search for the smallest diff or a plugin winner. The 48-cell pilot suggests these are separable outcomes: simple summary work saturated, while CSV-import work exposed continuation/latency differences; line counts did not track correctness or design quality. Expand task variety and judge both behavior and whether code boundaries fit the change.

## Paired task set

Use four task families, each with a frozen fixture, hidden behavioral checks, and a paired second request on a fresh session with the first patch applied and the same assigned condition retained:

1. **Notification lifecycle (new fixture):** create and deliver a notification when a domain event occurs; follow-up adds a second delivery channel with distinct retry/failure semantics. The minimal solution may be a method; justified separation may emerge around delivery policy or side effects. Avoid requiring a job/strategy abstraction in the prompt.
2. **Domain policy variation (new fixture):** add a real rule variation whose result depends on more than one domain input; follow-up introduces a second policy/customer with an exception. Include boundary cases that distinguish correct rule ownership from controller conditionals. Do not name a desired class or pattern.
3. **Reliable external export (new fixture):** export records to an external sink with partial failure and retry/idempotency requirements; follow-up adds a second export format or destination while preserving retry behavior. Specify observable guarantees and failure injection, not a prescribed adapter hierarchy.
4. **Real Rails holdout (optional, strongest transfer check):** isolated snapshot of a small existing Rails feature where a change crosses persistence, authorization, and UI. Use an authorization or state-transition behavior with meaningful existing conventions. Keep this outside the main pooled estimate if fixture boot cost, dependencies, or reviewer context differ; report it as a case study.

A short control task may reuse `report` only to calibrate prompt/checker drift, not as evidence of architectural discrimination. Do not use another tiny one-file task as a primary case.

## Sequential prompts

Freeze exact text and fixture state before runs. Example neutral first-stage requests:

- **Notification:** “When a booking is confirmed, record a notification for its attendee and deliver it through the existing in-memory gateway. Invalid addresses must not be delivered. Delivery failures should leave the notification retryable without duplicating successful deliveries. Implement this behavior and add coverage.” Follow-up: “A second gateway is now available for SMS. Some attendees have email disabled and SMS enabled; a gateway can fail independently. Support this case while preserving retry behavior for already successful deliveries.”
- **Policy:** “Calculate a service fee from the supplied order and account data. The fee is waived for accounts with an active exemption, except for orders marked expedited. Return the amount and retain the current caller contract. Add coverage for the relevant combinations.” Follow-up: “A second account tier now has a different fee rate and exemption rule. Add it while preserving existing behavior and make the rule outcomes explicit in tests.” Avoid this exact prompt if it collapses to a small formula; fixture should include an existing policy seam or enough real callers to make placement meaningful.
- **Export:** “Export eligible invoices to the supplied remote gateway. The gateway may accept a batch partially and may time out after accepting it. Repeating an export must not duplicate accepted invoices; rejected invoices should remain eligible for retry. Add coverage for partial acceptance and timeout.” Follow-up: “A second destination accepts a different row shape and has a different batch limit. Add support while keeping retries safe for both destinations.”
- **Rails holdout:** phrase as a user-observable feature/bug and acceptance cases, then ask for implementation and tests; preserve source conventions and authorization contract without naming layers/classes.

Pilot `csv_import` already has a follow-up (alternate header mapping) but is only a modest extension; retain as an external-boundary comparison, not a proxy for durable architecture. Its parser and validation exception distinctions must stay explicit in checks.

## Pairing and assignment

Use within-task paired comparisons: identical fixture commit, prompt, hidden checks, time/continuation policy, and fresh state for each condition. Randomize condition order and task order per agent; run repeated blocks, stratified by agent/model. Do not let a model see another condition's patch or transcript. Analyze task × condition × agent contrasts; do not pool agent/model differences as treatment effects. Keep failed and timed-out assignments in denominators, with infrastructure-confounded outcomes labeled. The unit is a run, while the task is the main generalization limit; a few tasks cannot establish broad superiority.

Each first request gets a follow-up in a new session seeded with its own first-stage patch. Record first-stage correctness separately and retain all assigned follow-up cells even when stage one failed. This distinguishes a design that remains adaptable from one that merely passes a one-shot checker.

## Measures (report side by side, no weighted winner score)

**Behavior:** hidden and visible contract pass/fail by requirement; regression count; failure atomicity/idempotency/retry cases; authorization or state invariants; first-turn and eventual correctness; follow-up correctness conditional and unconditional; continuations, agent execution time, and checker disposition. Preserve task-level results and denominators.

**Architecture / maintainability:** blinded reviewers assess (a) change is located at the domain/boundary that owns the rule, (b) dependencies and side effects are explicit/testable, (c) extension adds the second case without scattering conditionals or duplicating behavior, (d) abstractions have demonstrated use and proportionate scope, (e) existing conventions/callers remain coherent, and (f) unnecessary indirection/state/configuration. Review first patch and combined follow-up separately. Include changed files/lines as descriptive context only, never as a simplicity score. Ask reviewers to cite concrete code evidence and distinguish “could be abstracted” from a current defect.

Blind-review randomize patches and mask condition, agent, model, timing, and plugin artifacts. Two independent reviewers per patch; adjudicate disagreements with cited rubric evidence. Include a “no meaningful difference” rating. Report reviewer agreement and task-specific examples.

## Predeclared failure traps

- A passing checker with a tangled or duplicated implementation is not an architecture win; a clean abstraction with incorrect behavior is not a quality win.
- Do not reward classes, file count, line count, design-pattern names, or plugin-flavored prose by themselves. Penalize speculative frameworks and abstractions with only one trivial use.
- Ensure tests can reject common shortcuts: duplicate delivery after timeout, lost retry state, cross-destination leakage, incorrect rule precedence, caller/API breakage, invalid data mutation, and authorization bypass where applicable.
- Validate hidden checks against the stated contract and baseline behavior before treatment runs; fixtures should not secretly demand a preferred architecture.
- Keep follow-up prompt wording and supplied context equal across arms. No coaching that names a pattern after seeing an arm's first patch.
- Separate agent/model/runtime effects, infrastructure failures, task difficulty, and condition effects. No aggregate “winner” from this exploratory sample.
- If all three arms produce the same architecture and pass behavior, call the task nondiscriminating; do not reinterpret rubric preferences as a treatment effect.

## Likely concept bias checks

The notification concept can bias toward queues, outboxes, or strategy objects; describe delivery/retry guarantees, keep the gateway local and deterministic, and accept a simple design when it meets them. Domain-policy variation can bias toward an invented policy class; include realistic multiple inputs/callers and judge locality plus change cost, not class extraction. Reliable external export can privilege adapter abstractions and may conflate architecture with distributed-systems difficulty; make acceptance, timeout, idempotency, and retry semantics identical and fully deterministic in fixtures, and analyze separately from simpler tasks. For all three, pre-review prompts/checks without plugin exposure and document alternative correct designs.
