# Follow-up results

**Status:** 32 repeat trials and 12 investigation trials completed on 27 October 2026. The investigation responses have not been scored by a human.

## Campfire: 48 trials including the original pilot

Each model attempted each of four tasks three times. The first repeat grid passed 16/16; the second passed 15/16. All passing test-writing trials in the repeats produced an assertion failure with zero test errors after the mutation. See the individual records for checks and answers.

| Requested model | Passes | API-equivalent token estimate |
| --- | ---: | ---: |
| gpt-6-luna | 10/12 | $0.0419 |
| gpt-6.1-terra | 12/12 | $0.2677 |
| gpt-6.1-sol | 12/12 | $0.6427 |
| gpt-6-astra | 12/12 | $4.4143 |

Luna's two failures were on different tasks. In the original test-writing trial it declined to add a test because it found existing coverage; its two repeats added tests and passed. In the second-repeat location task it cited `app/controllers/rooms/opens_controller.rb:45`, while the checker required the model-level enforcement in `app/models/room.rb`. The exact answer and acceptance record are in the second repeat results. The remaining models passed all twelve of their trials.

These are four tasks on one application, not enough to prove the model-selection policy or establish production reliability. The feature grader tests specified behavior; it does not prove equal maintainability or test quality. Some agent runs reported browser tests blocked by ChromeDriver; the existing harness acceptance checks are the basis for the pass results.

The pilot and second repeat used a 600-second agent timeout. The first repeat used the existing task defaults: 600 seconds for location, 1,200 for test writing, and 1,800 for the feature. Its completed agent durations were all under 600 seconds, but the different configured limits remain a protocol deviation. Each resumed second-repeat cell was run with 600 seconds. A low-disk guard paused that grid after 13 cells; only the three unfinished cells were resumed.

## Investigation: 12 answers

All 12 model calls completed, three per requested model. Answers are synthetic Ruby payment-race investigations, not a benchmark of a live payment system. [Review the anonymous answers](investigation/blind_outputs/) using the [rubric](../investigation/evaluator/rubric.md) and [answer key](../investigation/evaluator/answer_key.md) before opening the unblinding key or raw response directories. An independent AI produced a [provisional blind review](blind-review.json); its scores and evidence are highly uniform and have not been calibrated against human judgments, so they are not a substitute for the planned human review.

The later [two-reviewer blind assessment](BLIND-REVIEW.md) is complete; it remains an AI assessment and has not been independently scored by a human.

## Costs and billing

Using the short-context standard API input, cached-input and output rates checked on 27 October 2026, the **48 Campfire trials** have an API-equivalent estimate of **$5.3666** and the **12 investigation trials** an estimate of **$0.5559**. Cached input is a subset of total input; output includes reasoning. These estimates omit long-context premiums, cache-write charges and tool costs and are not a statement of actual subscription charges or credits. All runs used the Codex ChatGPT login, not an API key.

## Files

- [First repeat trial data](repeat-1/summary.csv) and [second repeat trial data](repeat-2/summary.csv)
- [Original pilot results](../RESULTS.md)
- [Investigation manifest](investigation/manifest.json), which contains usage and hashes without model names
- [Investigation raw answers](investigation/raw_responses/) and [unblinding key](investigation/unblinding_key.json), for use only after review

Each repeat's `omitted-files.txt` identifies transcript files withheld by the conservative secret scanner. A scanner match is not proof that a secret is present; those files require review before publication.
