# Blind review of the payment-race investigations

**Completed 27 October 2026.** Two independent AI reviewers assessed the 12 anonymized responses against the existing five-dimension rubric before seeing the model mapping. This is an AI review, not the human review specified in the experiment design. Both reviewers used Luna, so they are not independent in model family or potential biases.

## Scores after unblinding

Each cell shows reviewer A / reviewer B, out of 20. The three columns are the three responses for that model, ordered by anonymous ID rather than execution order.

| Requested model | Response 1 | Response 2 | Response 3 |
| --- | --- | --- | --- |
| Luna | 18 / 17 | 20 / 19 | 19 / 17 |
| Terra | 19 / 19 | 19 / 19 | 19 / 19 |
| Sol | 20 / 20 | 19 / 19 | 20 / 20 |
| Astra | 20 / 19 | 20 / 19 | 19 / 19 |

These small differences are not evidence of a reliable model ranking. There is only one synthetic investigation, the prompt identifies the concurrency scenario, and the model-produced reviewers were not calibrated against human scores. A high rubric score is not proof that a proposed payment design is safe in production.

## What the reviewers found

Both reviewers gave all twelve answers their top score for identifying the race and describing an interleaving in the corrected review. The answers generally recognized that a stable-looking key cannot guarantee that the supplied fake gateway deduplicates requests. Most proposed a durable claim backed by uniqueness before contacting the gateway, and acknowledged that an uncertain external outcome needs reconciliation or a documented provider contract.

The main disagreements concerned how completely an answer specified conflict recovery, uncertain retries, and a regression test for an ambiguous gateway outcome. For example, in response `456aa04aa60a5aad` (Luna after unblinding), the wording “reconcile or retry using the same key” could be read as allowing a retry without a verified provider contract. The answer also acknowledges that safe resolution depends on unspecified provider behavior. A human reviewer should decide whether the caveat resolves the ambiguity.

## Review integrity and limitations

The first version of reviewer A's file assigned some evidence to the wrong anonymous IDs after assuming a file order. This was found before unblinding: reviewer A reopened all twelve responses by exact ID and replaced its assessment. The corrected review is preserved separately from reviewer B's independent review. This error is a reason to inspect the evidence, not merely trust the numeric totals.

The reviewers disagree on some dimension scores. They did not complete a joint adjudication and we did not average or otherwise reconcile their scores. The previous provisional AI review is a separate preliminary artifact, not one of these two reviews.

No human has independently scored the answers yet. For a human review, read only the anonymous answer files plus the rubric and answer key first; open the unblinding key and raw answers only after recording scores. Because the mapping has now been opened for this report, a new evaluator who has not seen this report is needed for genuinely blinded human review.

## Evidence

- [Anonymous answers](investigation/blind_outputs/)
- [Rubric](../investigation/evaluator/rubric.md) and [answer key](../investigation/evaluator/answer_key.md)
- [Corrected reviewer A](blind-review-a.json) and [reviewer B](blind-review-b.json)
- [Unblinding key](investigation/unblinding_key.json)
- [Original run and cost results](RESULTS.md)
