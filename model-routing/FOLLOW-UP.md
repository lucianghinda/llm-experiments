# Follow-up to the model-routing pilot

**Status:** both 16-cell repeat grids and all 12 investigation runs completed. The second grid stopped below 4 GiB after 13 cells; its three unfinished cells were resumed after space became available. Investigation answers await human blind review. See [follow-up results](follow-up-results/RESULTS.md).

## Existing tasks: two repeats

Keep the four pilot prompts, Campfire image `llmx-app-campfire:latest` (index digest `sha256:2f81affa534cf256462a9d175b44edc4d1430bbb99d296ad7483081c60000140`), branch `trial/base`, Codex CLI 0.164.0, common harness, timeouts and default reasoning settings. Use all four models on all four tasks twice: 32 new runs. Run sequentially, randomize each complete 16-cell grid with seeds `20261028` and `20261029`, and keep the two grids and the original pilot distinct in the records. Starting with the existing pilot, there will be three attempts per cell. Record the image digest and exact CLI version before each grid, and stop if either differs from the pilot or credentials are not a ChatGPT login. Do not start if fewer than 4 GiB is available; the existing image-build guidance recommends 12 GiB.

The test-writing prompt explicitly requests an added test. Leaving the tree untouched is a failure under that rubric even when the model identifies existing coverage. The existing mutation checker treats any nonzero mutated test command as a kill; independently inspect its mutation summary and require an actual assertion failure with no test errors before counting a pass. The three pilot passes had assertion failures and zero errors in their recorded mutated summaries, so this additional audit does not change the original outcomes. Report unclassifiable runs rather than quietly changing the prior result.

**Protocol deviation discovered after the first repeat grid started:** the pilot used a 600-second agent timeout for every task. The repeat runner initially used the task defaults of 600 seconds for location, 1,200 for test writing and 1,800 for the feature. Record each actual timeout and completion time. For cross-grid comparison, classify any result that requires more than the pilot's 600 seconds as outside the comparable limit. The second repeat grid should pass an explicit 600-second timeout. Do not claim this difference had no effect on timeouts.

## Investigation: three repeats per model

Use the exact prompt and source in `investigation/model_workspace/`. The task is a synthetic, dependency-free Ruby reproduction of a Rails-style payment service, not an actual Rails application or production payment gateway. The test uses an explicit barrier to reproduce the race, and the evaluator's reference mutex test demonstrates thread-level serialization only. It is not evidence of a cross-process or distributed solution.

All four model IDs receive the same starting files and prompt, with three fresh independent runs each: 12 runs. Shuffle all 12 with a recorded seed `20261030`. The model workspace must contain only `model_workspace/` and its own generated temporary files. Keep `investigation/evaluator/`, including the answer key and rubric, inaccessible to the agent. Do not mount the parent directory into its environment.

Use the same pinned CLI, model settings, login method, turn limits and tools for all runs. Record source, prompt, grader and image hashes; save full transcripts outside the model workspace. If the existing Campfire image is used, ensure only the synthetic workspace is visible, or disclose the extra context and treat it as a limitation. Validate agent isolation and a smoke run before proceeding. Never publish authentication data or tokens.

Blind the responses by assigning randomly generated IDs before an evaluator reads them. Preserve a separate model-to-ID mapping and do not consult it until the scoring is complete. Have a human judge all five rubric dimensions with evidence; a second reviewer should independently score or adjudicate disagreements. Capture false positives and unsupported claims. Do not substitute an uncalibrated model judge for this human evaluation.

## Accounting and interpretation

Use Codex subscription usage; report input, cached-input and output tokens. API-equivalent estimates are not subscription charges. Record the pricing date and assumptions, and keep the user's $10 API-spend ceiling: these subscription-authenticated runs should not use an API key or be billed as API requests. Plan or credit consumption is distinct and should be reported if visible. Stop on an invalid login, unexpected API-key authentication, unavailable model, or low disk space.

Report per-task outcomes, mutation errors, failures, and the complete 48-run total for the four existing tasks including the pilot. Report the 12 investigation scores separately. Three repeats show variability but five tasks do not establish a general model-ranking or prove the policy. Do not pool the synthetic investigation's human scores with the Campfire pass rate as if they measured the same thing.
