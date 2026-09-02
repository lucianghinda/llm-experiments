# Adjudication: what the regex misses score when read

`coverage.rb` decides whether a fact is present by matching a regular expression written
from the vocabulary of ordinary technical prose. Several variants in this experiment exist
to *replace* that vocabulary. The checker can therefore mark an output down for obeying the
instruction under test.

This file records what all **116 regex misses** score when the output is read instead of
matched. Each was read against the source file under test. `ruby adjudicate.rb` totals
these verdicts back onto the regex floors.

## The headline

**26 of 116 misses were real facts stated in other words. 90 were genuine absences.**

The earlier experiment found that re-reading moved its numbers a long way, and warned that
every regex content number is a floor. That warning holds here, but the size of the
correction is much smaller than it was there — and, more importantly, it is **not uniform
across targets**:

| Target | misses | really present | rate |
|---|---|---|---|
| 01 rails concern | 39 | 2 | 5% |
| 02 method, domain | 35 | 5 | 14% |
| 03 method, algorithm | 33 | 12 | 36% |
| 04 query object | 9 | 7 | 78% |

Quoting one blanket "the checker is biased against the treatment" correction would have
been wrong in both directions. On target 04 the regex badly understates the instructed
arms; on target 01 it is very nearly right.

Two facts account for most of the genuine absences, and both are missed by the control
arms as well as the instructed ones:

- **"runs in memory, not in SQL"** (target 02) — 21 of that target's 35 misses. Default,
  Concise and Learning miss it too.
- **"created_at stored but never read"** (target 01) — 17 misses, none of them a false
  negative. The outputs mention storing a timestamp; they do not say it is dead data.

## The checker also errs the other way, and this correction does not fix that

The adjudication above only re-reads the **misses**. It cannot find a fact the regex
credited to an output that does not contain it. At least one fact has that problem, and it
was found by spot-check rather than by audit:

`"created_at stored but never read" => /created_at/i` credits any mention of the token.
Four of the seven cells that score it merely list the column among the stored fields:

| Cell | What it actually says |
|---|---|
| run-1 01 concise | "Stores status, body, whitelisted headers, body hash, and `created_at`, with a 24-hour TTL." |
| run-1 01 proactive | "Stores status, body, allowlisted headers, the body hash, and `created_at`, with a 24-hour TTL." |
| run-2 01 default | "then writes `{status, body, headers, body_hash, created_at}` with a 24-hour TTL." |
| run-2 01 proactive | same shape |

Three cells state the insight properly and are true hits, for example run-1 01 default:
"`created_at` is stored in the entry but not read anywhere in this file — expiry is handled
entirely by the cache TTL."

So the floor contains false positives as well as false negatives, and here the false
positives fall on the **control-ish** arms while the false negatives fall on the
**instructed** arms. A full audit would have to re-read all 576 fact judgements, not only
the 116 misses. That was not done. Both numbers in `adjudicate.rb` therefore carry this
leniency, and the honest reading is that the content differences between neighbouring arms
are smaller than any single table makes them look.

## Method

Four independent readers, one per target, each given the six-fact list, the source file
under test, and the list of cells with their misses. Each was told to be strict — a vague
gesture is not the fact — but not to require the regex's vocabulary, and to quote the
sentence it relied on for every PRESENT. The target-01 reader cross-checked every verdict
with path-labelled `grep` rather than batch recall, after noticing that reading many
similarly-structured files together risked attributing one file's text to another.

## Verdicts

Format: `path | fact | verdict`. Quotes for the PRESENT calls are in the run log; the
full quoted evidence for the four targets was produced by the readers and is summarised
above where it changed a conclusion.

### Target 01

```
runs/run-1/01-rails-concern/01-default.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/02-concise.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/04-learning.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/05-proactive.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/06-style-ste.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/06-style-ste.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/07-style-asd.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/07-style-asd.md | replay skips the rate limit callback | ABSENT
runs/run-1/01-rails-concern/08-style-asd-hatch.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/08-style-asd-hatch.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/09-style-asd-bare.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/09-style-asd-bare.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/09-style-asd-bare.md | replay skips the rate limit callback | ABSENT
runs/run-1/01-rails-concern/10-prompt-ste.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/10-prompt-ste.md | Set-Cookie kept out of the cache | PRESENT
runs/run-1/01-rails-concern/11-prompt-asd.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/11-prompt-asd.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/12-prompt-asd-hatch.md | created_at stored but never read | ABSENT
runs/run-1/01-rails-concern/12-prompt-asd-hatch.md | Set-Cookie kept out of the cache | ABSENT
runs/run-1/01-rails-concern/12-prompt-asd-hatch.md | replay skips the rate limit callback | ABSENT
runs/run-2/01-rails-concern/01-default.md | Set-Cookie kept out of the cache | ABSENT
runs/run-2/01-rails-concern/02-concise.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/02-concise.md | Set-Cookie kept out of the cache | ABSENT
runs/run-2/01-rails-concern/04-learning.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/06-style-ste.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/06-style-ste.md | Set-Cookie kept out of the cache | PRESENT
runs/run-2/01-rails-concern/07-style-asd.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/07-style-asd.md | Set-Cookie kept out of the cache | ABSENT
runs/run-2/01-rails-concern/08-style-asd-hatch.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/09-style-asd-bare.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/09-style-asd-bare.md | Set-Cookie kept out of the cache | ABSENT
runs/run-2/01-rails-concern/10-prompt-ste.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/10-prompt-ste.md | Set-Cookie kept out of the cache | ABSENT
runs/run-2/01-rails-concern/11-prompt-asd.md | no lock on concurrent first requests | ABSENT
runs/run-2/01-rails-concern/11-prompt-asd.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/11-prompt-asd.md | Set-Cookie kept out of the cache | ABSENT
runs/run-2/01-rails-concern/12-prompt-asd-hatch.md | created_at stored but never read | ABSENT
runs/run-2/01-rails-concern/12-prompt-asd-hatch.md | Set-Cookie kept out of the cache | ABSENT
runs/run-2/01-rails-concern/12-prompt-asd-hatch.md | replay skips the rate limit callback | ABSENT
```

### Target 02

```
runs/run-1/02-single-method-domain/01-default.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/02-concise.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/03-explanatory.md | runs in memory, not in SQL | PRESENT
runs/run-1/02-single-method-domain/04-learning.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/05-proactive.md | runs in memory, not in SQL | PRESENT
runs/run-1/02-single-method-domain/06-style-ste.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/07-style-asd.md | why public_send and not &symbol | ABSENT
runs/run-1/02-single-method-domain/07-style-asd.md | array subtraction uses AR equality | ABSENT
runs/run-1/02-single-method-domain/07-style-asd.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/08-style-asd-hatch.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/09-style-asd-bare.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/10-prompt-ste.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/11-prompt-asd.md | why public_send and not &symbol | ABSENT
runs/run-1/02-single-method-domain/11-prompt-asd.md | sorts at two levels | PRESENT
runs/run-1/02-single-method-domain/11-prompt-asd.md | array subtraction uses AR equality | ABSENT
runs/run-1/02-single-method-domain/11-prompt-asd.md | runs in memory, not in SQL | ABSENT
runs/run-1/02-single-method-domain/12-prompt-asd-hatch.md | why public_send and not &symbol | ABSENT
runs/run-1/02-single-method-domain/12-prompt-asd-hatch.md | root record decides the section | ABSENT
runs/run-1/02-single-method-domain/12-prompt-asd-hatch.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/01-default.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/02-concise.md | fallback root when real root missing | PRESENT
runs/run-2/02-single-method-domain/02-concise.md | why public_send and not &symbol | ABSENT
runs/run-2/02-single-method-domain/02-concise.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/05-proactive.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/07-style-asd.md | why public_send and not &symbol | ABSENT
runs/run-2/02-single-method-domain/07-style-asd.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/08-style-asd-hatch.md | why public_send and not &symbol | ABSENT
runs/run-2/02-single-method-domain/08-style-asd-hatch.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/09-style-asd-bare.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/10-prompt-ste.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/11-prompt-asd.md | fallback root when real root missing | PRESENT
runs/run-2/02-single-method-domain/11-prompt-asd.md | why public_send and not &symbol | ABSENT
runs/run-2/02-single-method-domain/11-prompt-asd.md | root record decides the section | ABSENT
runs/run-2/02-single-method-domain/11-prompt-asd.md | runs in memory, not in SQL | ABSENT
runs/run-2/02-single-method-domain/12-prompt-asd-hatch.md | runs in memory, not in SQL | ABSENT
```

### Target 03

```
runs/run-1/03-single-method-algorithm/01-default.md | linear cost / k never rewinds | ABSENT
runs/run-1/03-single-method-algorithm/02-concise.md | integer division floors the result | ABSENT
runs/run-1/03-single-method-algorithm/04-learning.md | linear cost / k never rewinds | ABSENT
runs/run-1/03-single-method-algorithm/05-proactive.md | linear cost / k never rewinds | ABSENT
runs/run-1/03-single-method-algorithm/08-style-asd-hatch.md | unbounded until loop would spin forever | PRESENT
runs/run-1/03-single-method-algorithm/08-style-asd-hatch.md | linear cost / k never rewinds | ABSENT
runs/run-1/03-single-method-algorithm/09-style-asd-bare.md | integer division floors the result | PRESENT
runs/run-1/03-single-method-algorithm/09-style-asd-bare.md | unbounded until loop would spin forever | PRESENT
runs/run-1/03-single-method-algorithm/09-style-asd-bare.md | linear cost / k never rewinds | ABSENT
runs/run-1/03-single-method-algorithm/10-prompt-ste.md | linear cost / k never rewinds | PRESENT
runs/run-1/03-single-method-algorithm/11-prompt-asd.md | integer division floors the result | PRESENT
runs/run-1/03-single-method-algorithm/11-prompt-asd.md | unbounded until loop would spin forever | ABSENT
runs/run-1/03-single-method-algorithm/11-prompt-asd.md | worked example with real strings | PRESENT
runs/run-1/03-single-method-algorithm/11-prompt-asd.md | linear cost / k never rewinds | ABSENT
runs/run-1/03-single-method-algorithm/12-prompt-asd-hatch.md | integer division floors the result | ABSENT
runs/run-1/03-single-method-algorithm/12-prompt-asd-hatch.md | unbounded until loop would spin forever | PRESENT
runs/run-1/03-single-method-algorithm/12-prompt-asd-hatch.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/01-default.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/02-concise.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/03-explanatory.md | unbounded until loop would spin forever | PRESENT
runs/run-2/03-single-method-algorithm/06-style-ste.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/07-style-asd.md | integer division floors the result | PRESENT
runs/run-2/03-single-method-algorithm/07-style-asd.md | unbounded until loop would spin forever | PRESENT
runs/run-2/03-single-method-algorithm/07-style-asd.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/08-style-asd-hatch.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/09-style-asd-bare.md | unbounded until loop would spin forever | ABSENT
runs/run-2/03-single-method-algorithm/09-style-asd-bare.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/10-prompt-ste.md | unbounded until loop would spin forever | PRESENT
runs/run-2/03-single-method-algorithm/10-prompt-ste.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/11-prompt-asd.md | integer division floors the result | PRESENT
runs/run-2/03-single-method-algorithm/11-prompt-asd.md | unbounded until loop would spin forever | ABSENT
runs/run-2/03-single-method-algorithm/11-prompt-asd.md | linear cost / k never rewinds | ABSENT
runs/run-2/03-single-method-algorithm/12-prompt-asd-hatch.md | linear cost / k never rewinds | ABSENT
```

### Target 04

```
runs/run-1/04-query-object/07-style-asd.md | unknown section keys are skipped | PRESENT | "If the key is not one of the top-level sections, the method ignores the block (line 81)."
runs/run-1/04-query-object/09-style-asd-bare.md | unknown section keys are skipped | PRESENT | "If the key is not a top-level key, the code ignores the block."
runs/run-1/04-query-object/11-prompt-asd.md | includes() avoids N+1 queries | PRESENT | "This prevents many small database queries."
runs/run-1/04-query-object/12-prompt-asd-hatch.md | unknown section keys are skipped | PRESENT | "If the key is not a top-level key of the result Hash, the method ignores that block."
runs/run-2/04-query-object/04-learning.md | exclusion lists are memoised | PRESENT | "The four excluded_* memos each call excluded_records independently, so this issues 2 exclusion queries per platform rather than 1."
runs/run-2/04-query-object/09-style-asd-bare.md | unknown section keys are skipped | PRESENT | "If the key is not in the Hash, the code discards the block (line 81)."
runs/run-2/04-query-object/11-prompt-asd.md | includes() avoids N+1 queries | ABSENT | ""
runs/run-2/04-query-object/11-prompt-asd.md | exclusion lists are memoised | ABSENT | ""
runs/run-2/04-query-object/11-prompt-asd.md | unknown section keys are skipped | PRESENT | "The code discards a block when its section key is not a top-level key."
```

