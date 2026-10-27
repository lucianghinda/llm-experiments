# Model routing pilot results

**Status: exploratory pilot completed on 27 October 2026.** This is one run per model and task, not the 192-trial experiment in the design. It does not establish which model is best or validate the proposed model-routing policy.

## What we ran

Four models each attempted the same four existing Campfire tasks in fresh containers: two code-location questions, a test-writing task, and a cross-layer Rails feature. The test-writing check requires an added test and verifies it against a mutation. The feature check exercises the requested behavior and regression suite. These tasks do not include the planned difficult, high-impact investigation category.

All trials used the existing `llmx-app-campfire:latest` image, isolated branch `trial/base`, clean starting tree and imported commit `eeef2b221f3cf68d6a2ac11bb702612be83379a5`, and Codex CLI 0.164.0. Codex was authenticated using a ChatGPT subscription. Each model ID was explicitly requested and recorded; the JSON transcript does not independently certify the serving model. No common reasoning effort was explicitly set, so model defaults may differ. The first Luna location trial was run as a setup check, then the other 15 task/model pairs were shuffled with seed 20261027 and run sequentially. This is not the same order as shuffling all 16 together.

The prior attempts with CLI 0.147.0 aborted before a valid model response: the first had a stale container login and the second reported the requested model unsupported. They are excluded from the 16 results and are not model failures. A newer CLI in a temporary tools volume allowed the pilot to proceed.

## Results

| Task | Luna | Terra | Sol | Astra |
| --- | --- | --- | --- | --- |
| Locate direct-room type rule | Pass | Pass | Pass | Pass |
| Locate generated secret | Pass | Pass | Pass | Pass |
| Add a regression test | Fail | Pass | Pass | Pass |
| Add room topic across layers | Pass | Pass | Pass | Pass |

For the failed test-writing trial, Luna found existing coverage and said another test would duplicate it. The task requested an added test, and the acceptance check found no new or modified test. That explains the failure; it does not show that Luna could never write a suitable test. The three other models added tests that passed the mutation check.

All four models' room-topic implementations passed the feature check. Luna did not add test files in its patch, while Terra, Sol and Astra did. The check passing establishes the behavior covered by that verifier; it does not establish equal maintainability, review quality, or completeness.

## Usage and estimated cost

The [trial data](pilot-results/summary.csv) records input, cached-input and output tokens and the agent and host elapsed time for every cell. Estimated total API-equivalent token cost was **$1.6223**, calculated using the standard short-context prices from [OpenAI's pricing page](https://developers.openai.com/api/docs/pricing) as checked on 27 October 2026. Cached input is a subset of input; reasoning tokens are included in output. Estimates omit tool charges, cache writes, processing premiums and any long-context pricing. They do not measure the cost or credits charged to the ChatGPT subscription.

The saved trial directories contain acceptance records, prompts, answers and sanitized transcripts and diffs when available. The Terra generated-secret transcript matched a conservative secret scanner and was omitted pending review; see [omitted files](pilot-results/omitted-files.txt). No transcript from the failed authentication attempts is published.

## Limits and next steps

- One attempt per cell is not enough to estimate reliability or separate model effects from randomness. We did not run the planned three repeats or holdout.
- Two location tasks were too easy to distinguish the models in this run. The task mix is not representative of all Ruby or Rails work.
- There is no high-impact investigation task and no live test of `AGENTS.md` routing or subagent selection.
- Common reasoning effort, independent model identity verification, browser-system test coverage, and graders should be checked before a larger run. Astra reported that browser tests were blocked by ChromeDriver; this did not prevent the existing acceptance check from passing.
- Available disk space was below the existing image-build recommendation. We used an existing image rather than building a new one.

The useful next step is to add and validate a difficult investigation task, strengthen feature-quality checks, then repeat a predeclared grid on pinned model and harness versions. Do not convert this pilot into a claim that the article's policy is proven.
