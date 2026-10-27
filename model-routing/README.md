# Does choosing a model by task make Ruby coding work cheaper without losing quality?

**Status:** exploratory pilot and follow-up completed; see [pilot results](RESULTS.md), [follow-up results](follow-up-results/RESULTS.md), and [blind review](follow-up-results/BLIND-REVIEW.md). The proposed 192-trial main grid has not been run. This document preserves the original design.

## The question

The article proposes Luna for bounded exploration, Terra for scoped implementation, Sol for harder implementation and review, and Astra for difficult, high-impact investigation. These are plausible starting points, not established properties of the models. Can a routing policy based on the shape of a Ruby or Rails task achieve acceptable results at lower total cost than using the same model for every task?

The counter-hypotheses matter just as much:

- Luna may be good enough even for some tasks assigned to more expensive models.
- A cheaper run may fail often enough that retries and review erase its savings.
- A single stronger model may be both simpler and more reliable at an acceptable price.
- Task shape, reasoning effort, prompt and harness may matter as much as the model.

The result could be that the proposed routing policy is useful, that a different policy works better, or that this test cannot distinguish them. Do not design the scoring around making the article's recommendation win.

## What we will compare

### Experiment A: model choice on the same task

Run every task against all four models in the same coding-agent harness: `gpt-6-luna`, `gpt-6.1-terra`, `gpt-6.1-sol`, and `gpt-6-astra`. Each trial receives the same task prompt, starting commit, tools, time limit, and visible tests. Model is the intended treatment. Record reasoning effort and verify the exact supported setting for each model before running; use the same supported effort where possible. If equal settings are unavailable, document that limitation and do not interpret the comparison as model alone.

The four conditions below are simulated policies derived from the trial grid, not four live multi-agent systems:

| Policy | Model for every task, or by category |
| --- | --- |
| Proposed routing | Luna for exploration; Terra for scoped implementation; Sol for complex implementation and review; Astra for difficult investigation |
| Luna only | Luna for every category |
| Sol only | Sol for every category |
| Astra only | Astra for every category |

All four models also run tasks outside their proposed category. This cross-testing is essential: without it, a difference between agents could simply be a difference in task difficulty.

For policy comparisons, preassign each task to one category before running. Use the empirical per-task mean of its three runs for the model assigned by each policy; average tasks equally. This estimates a single attempt per task, not a cherry-picked best run. It does not measure orchestration or an automatic routing decision.

### Experiment B: does Codex follow the routing instructions?

Run this as a separate follow-up only after Experiment A. Compare a root agent given an explicit routing instruction and configured `.codex/agents/*.toml` files with the same root agent and task without those instructions. Record whether it delegates, which agent and model actually run, root and child token use, total cost, and task outcome. The routing instruction is guidance, so non-delegation and mismatches are outcomes, not missing data. Include setup and handoff costs. Do not claim Experiment A proves this live workflow works.

## Task set

Start with 16 tasks, four in each preassigned category. They should come from real or realistic Ruby and Rails work, not examples chosen because a particular model will win. Freeze the tasks, app commits, prompts and acceptance tests before the main run. Use at least two applications if the existing clean-room tooling can support them; otherwise explicitly limit the findings to one app. The existing `convention-navigation` experiment and its Campfire checkout are a useful starting point, subject to pinned source, licensing, and available tests.

| Category | Candidate tasks | What counts as success |
| --- | --- | --- |
| Exploration, Luna | Locate where an access rule is enforced; trace a job enqueue path; identify the caller of a generated secret; trace a request to its persistence boundary | Correct file and symbol, with evidence and no invented execution path; hidden answer key covers valid alternatives |
| Scoped implementation, Terra | Add a model validation; add a filter using existing conventions; fix a small authorization error; add a test for a documented edge case | Existing suite and hidden behavioral tests pass; targeted mutation confirms the new test detects the defect where applicable |
| Complex implementation or review, Sol | Correct a retry-related duplicate action; change a cross-layer feature; review a seeded authorization regression; repair a query regression without changing results | For edits, hidden tests verify behavior and regressions. For review, predefined seeded defects must be identified, with false positives recorded |
| High-impact investigation, Astra | Diagnose a seeded concurrency race; analyze a migration and rollout hazard; identify a transaction boundary that leaves inconsistent state; trace a multi-step data-retention failure | Identify the actual cause and evidence, distinguish assumptions, and propose a verification or fix that meets a prewritten rubric |

These are task designs, not claims that these exact defects exist in Campfire. First confirm feasibility on the chosen pinned fixtures. For each task, maintain a visible prompt, initial state, acceptance criteria, hidden verifier, and a reference solution or adjudication key. Confirm the seeded issue fails before the reference fix and passes after it. Keep graders outside the agent's workspace and restore any agent-modified tests or scoring infrastructure before verification. For investigation and review, use blind human adjudication against a frozen rubric, with a second reviewer resolving disagreements; never use mere verbosity or plausible wording as success.

Set aside four additional tasks, one per category, as a holdout. Do not use them to tune prompts, categories, graders, or thresholds. If only the pilot is funded, the 16-task grid is exploratory; do not call the holdout confirmatory after changing the policy based on it.

## Main grid and execution

- **Pilot:** 4 tasks, one per category, × 4 models × 1 run = 16 trials. Validate setup and graders only; do not use pilot results to claim model differences. Freeze any fixes before the main grid.
- **Main grid:** 16 tasks × 4 models × 3 independent repeats = 192 trials. The sample is a practical starting point, not a power calculation. Report uncertainty and avoid strong general claims if intervals are wide.
- **Holdout, optional after a frozen policy:** 4 tasks × 4 models × 3 repeats = 48 more trials. Use only if cost and access permit; report it separately.
- Randomize model order within each task and repeat, with a recorded seed. Start each run from the same clean snapshot in a fresh isolated environment, with no earlier trial's changes, conversation, cache state or logs visible to the agent. Pin tool versions, app dependencies, model IDs, reasoning effort, limits, source revision, prompts and grader versions.
- Make visible project instructions and subagent settings identical across Experiment A conditions. Disable hidden cross-agent delegation for this comparison or record it and treat it as a different treatment. A runner should verify the actual model used instead of assuming the requested model was honored.
- No live credentials, network side effects or destructive production operations in task fixtures. Use sandboxed, synthetic services for payment, email and external APIs. Separate secret-bearing raw logs from sanitized artifacts.

Before running the grid, verify account access and token usage reporting, run each model's tiny smoke test, calculate a maximum spend from measured pilot consumption plus a margin, and set a hard budget and per-run limits. Do not assume the article's 100K/20K example represents this workload. API pricing is not necessarily Codex subscription billing; label estimated API-list-price costs separately from observed billing or subscription usage.

## Measurements and scoring

For every attempt, retain a trial ID, task, category, requested and actual model, effort, prompt and source hashes, timestamps, exit status, evaluator version, pass/fail/invalid status, transcript or patch, input/cached-input/output/reasoning usage where available, tool charges, calculated cost, wall time and review time if a human records it. Count reasoning as output where the provider does so, without adding it twice. Check whether input counts include cached tokens before calculating cost. Snapshot the applicable price table and date, cache-write and service-tier assumptions. If usage or prices are unavailable, mark cost unknown rather than zero.

Classify outcomes in advance:

- **Pass:** all mandatory behavioral and safety checks succeed, or the blinded review rubric is met.
- **Fail:** agent started but the answer or patch does not meet the rubric, including timeout or task-level failure.
- **Invalid infrastructure attempt:** authentication, service, or sandbox failure prevents a fair trial. Preserve the record and reason, retry with a new ID under the same condition, and report invalid counts and spent cost separately. Do not silently remove agent failures.

Primary outcomes are task-level pass rate and **mean cost per assigned task including failed attempts**, reported together. Also report cost per verified success as total valid-trial cost divided by total passes; if there are no passes, report it as undefined. Do not calculate cost only from passing runs. Report median and tail wall time, per-category outcomes, false-positive review findings, and review time separately. Human review effort is not automatically converted into dollars.

## Analysis and decision rules

Before the main run, choose and record practical thresholds. Proposed starting thresholds for discussion: the routing policy's pass rate should be within 5 percentage points of Sol-only and its mean cost per task at least 25% lower. These numbers are design choices, not statistically established or proof of equivalence. For high-impact investigation, also report pass rates and missed critical findings separately; an aggregate saving cannot hide a severe regression.

Compute each policy's quality and cost by averaging task-level means with the predeclared category mix. Report the mix, category-level results, number of trials, and paired task differences. Use a paired bootstrap resampling **tasks** within category, not individual repeats as independent tasks, to show uncertainty for policy differences; three repeats describe run variability, not three new tasks. With four tasks per category, intervals will be unstable. Report them as exploratory, and do not claim the 5-point non-inferiority threshold is met unless a prespecified appropriate confidence interval for the paired quality difference excludes a loss worse than 5 points. If uncertainty includes both success and failure of the threshold, call the result inconclusive.

If the proposed policy does not meet both quality and cost criteria, report that. If a different policy looks better, present it as an exploratory candidate and evaluate it on untouched holdout tasks before presenting it as validated. Report individual task outcomes and failures even when the aggregate favors the proposal. Do not select models after seeing the same data and then call the resulting policy confirmed.

## Deliverables and repository fit

Follow this repository's conventions: a dedicated `model-routing/` directory with this design in `README.md`; `PROMPTS.md` with exact frozen prompts; task fixtures and hidden check definitions; Ruby standard-library scripts for orchestration and measurement; `results-raw/` and sanitized results according to the repository's privacy rules; and a `RESULTS.md` that distinguishes pilot, preregistered main grid, and holdout. Reuse `containers/` and the existing trial infrastructure where it can provide the same harness and clean state; assess the code and supported model configuration before claiming it can run this experiment.

Implementation would need task fixtures, verifiers, actual model selection, usage capture, isolation checks, and a dry-run grid before any paid trial. This document does not implement those pieces or authorize spending.

## References

- [Agents on Rails benchmark and methodology](https://rubyonrails.org/ai)
- [Rails AI evals methodology](https://github.com/rails/ai-evals/blob/main/methodology.md)
- [OpenAI evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices)
- [OpenAI API pricing](https://developers.openai.com/api/docs/pricing)
- [Codex subagent configuration](https://learn.chatgpt.com/docs/agent-configuration/subagents)
