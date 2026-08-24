# Does "king - man + woman = queen" hold when you check it yourself?

**Status: run. 18 analogies and 30 held-out plural pairs, on GloVe 50d. Tables in
[`results/tables.md`](results/tables.md).**

The short version. The famous analogy is a hit only under a convention nobody
mentions: the three input words are removed from the results first. Keep them in
and the nearest point to `woman - man + king` is **king**. Across 18 analogies,
top-1 accuracy falls from 11/18 to 8/18 when the inputs stay in the running, and
in 6 of 18 the winner is one of the inputs.

The second experiment, the one the talk spends less time on, holds up much
better. A single direction taken from `cats - cat` separates plural from
singular on 29 of 30 pairs it never saw — including 15/15 irregular plurals,
where there is no letter `s` to lean on.

This is a Ruby replication of the two word-vector demos in Grant Sanderson's
[Visualizing transformers and attention](https://www.youtube.com/watch?v=KJtZARuO3JY)
talk, whose manim source is
[`_2024/transformers/embedding.py`](https://github.com/3b1b/videos/blob/master/_2024/transformers/embedding.py).

## The question

Two claims are made about embedding spaces, and they are usually presented as
one claim.

1. **Analogy arithmetic.** `b - a + c` lands on the word that completes the
   analogy: `woman - man + king` lands on `queen`.
2. **Directions carry meaning.** The difference between one pair of words is a
   reusable direction that scores other words on the same property.

The first is the famous one and the weaker one. The second is the one that
actually generalises. Separating them is the point of this experiment.

## The design

Same model as the talk: **GloVe 6B, 50 dimensions, 400k words**, which is what
`Word2VecScene` in the manim source loads (`glove-wiki-gigaword-50`). Not GPT's
embedding matrix — the talk explains GPT-3's 12,288-dimensional embeddings but
demonstrates on GloVe, and so does this.

**Analogies.** 18 quadruples over 5 relations (gender, capital, comparative,
past tense, plural). For each, compute `b - a + c` and rank all 400,000 words
against it, twice: once with `a`, `b`, `c` still in the running, once with them
excluded. Recording both is the whole experiment. `gensim`'s `most_similar`
drops them silently; the `find_nearest_words` helper in the manim source does
not.

Ranking is done under both Euclidean distance — matching the source's
`((data - vector)**2).sum(1)` — and cosine, which is what the analogy literature
uses.

**The plural direction.** Take `cats - cat` as a candidate direction, then score
30 held-out pairs by dot product: does the plural score above the singular? Two
things vary. The direction is either that single seed pair (what the talk does)
or the mean of 5 separate training pairs. The score is either a raw dot product
(what the talk does) or cosine, which removes vector length from the comparison.

Half the test pairs are irregular — `man/men`, `mouse/mice`, `foot/feet`,
`criterion/criteria`. A direction built from `cats - cat` might only be
detecting a trailing `s`; irregular plurals separate that explanation from the
grammatical one.

No pair is reused: the seed is in neither list, and the 5 training pairs are
disjoint from the 30 test pairs.

## What the numbers say

### The analogy is weaker than its reputation

| metric | inputs excluded | inputs kept |
|---|---|---|
| euclidean | 11/18 (61%) | 8/18 (44%) |
| cosine | 12/18 (67%) | 8/18 (44%) |

With the inputs left in, the nearest word is one of them in 6 of 18 cases. That
includes the headline example: `woman - man + king` has `queen` at rank 1 once
`king` is removed, and `king` at rank 1 when it is not. The arithmetic points in
the right direction without travelling far enough to leave its own inputs
behind.

The misses are informative too. `paris - france + spain` gives `aires`, as in
Buenos Aires. `longer - long + short` puts `shorter` at rank 82 and returns
`actually`. `bigger - big + small` prefers `larger` to `smaller` — the right
relation applied to the wrong end of the pair.

### The direction generalises, and not because of spelling

| direction | score | all pairs | regular | irregular |
|---|---|---|---|---|
| seed (`cats - cat`) | dot | 29/30 (97%) | 14/15 (93%) | 15/15 (100%) |
| seed (`cats - cat`) | cosine | 29/30 (97%) | 14/15 (93%) | 15/15 (100%) |
| averaged (5 pairs) | dot | 29/30 (97%) | 14/15 (93%) | 15/15 (100%) |
| averaged (5 pairs) | cosine | 29/30 (97%) | 14/15 (93%) | 15/15 (100%) |

One pair fails, and it is the same pair every time: **leaf / leaves**. The
likely reason is polysemy rather than plurality — GloVe is uncased and
untagged, so `leaves` carries the verb ("he leaves") in the same vector as the
noun.

Two negative results worth stating. Averaging five training directions instead
of using one seed pair changed no verdict, only margins: the single pair the
talk uses is not a shortcut that costs accuracy here. And cosine agreed with the
raw dot product on all 30 pairs in both conditions, which is mild evidence that
the separation is about direction and not about frequent words having longer
vectors.

## Caveats

- **This measures GloVe, not an LLM.** 50 dimensions trained on 6B tokens of
  Wikipedia and Gigaword. It is the model the talk demonstrates on, and it is
  not what a transformer learns internally.
- **18 and 30 are small.** These are illustrative counts on hand-picked words,
  not a benchmark, and there is no significance test. The exclusion effect is
  not a sample estimate — it is a deterministic property of the same 18 items
  scored two ways, which is why it is reported as a count and not an interval.
- **The analogy set is easy on purpose.** Relations were chosen because they are
  the ones usually claimed to work. A harder set would score lower, so 61% is a
  ceiling, not an average over English.
- **Ties resolve in the expected word's favour.** `rank_of` counts strictly
  closer words. Exact float ties across 400k words are vanishingly rare; the
  choice is documented rather than relied on.
- **The vocabulary is uncased and untagged**, so every polysemous word carries
  all its senses in one vector. `leaves` is the visible cost of that here.

## Layout

```
words.yml            Every word both experiments touch. Nothing is hardcoded in a script.
vectors-slice.txt    The 116 rows words.yml names, copied verbatim from the table (49KB).
scripts/fetch.rb     Pulls only the 50d entry out of glove.6B.zip, via HTTP Range.
scripts/lib/vectors.rb  Table, vector arithmetic, whole-vocabulary ranking. Stdlib only.
scripts/slice.rb     Cuts vectors-slice.txt out of the full table.
scripts/run.rb       Runs both experiments, writes results/*.json. Measures, does not judge.
scripts/report.rb    Turns results/*.json into results/tables.md.
results/analogy.json     Per-analogy ranks, both metrics, both exclusion settings.
results/direction.json   Per-pair scores, both directions, both metrics.
results/tables.md        Generated. Every number quoted above comes from here.
data/                Gitignored. The 163MB table.
```

## Running it

Without the download — reproduces the committed direction results from the
49KB slice, and fails loudly if they disagree:

```
ruby word-vector-arithmetic/scripts/run.rb --slice
```

The whole thing, download included:

```
ruby word-vector-arithmetic/scripts/fetch.rb   # ~65MB over the wire, ~30s
ruby word-vector-arithmetic/scripts/run.rb     # ~47s: 36 scans of 400k words
ruby word-vector-arithmetic/scripts/slice.rb   # refresh the committed slice
ruby word-vector-arithmetic/scripts/report.rb  # regenerate results/tables.md
```

`fetch.rb` reads the zip's central directory over HTTP Range and asks for just
the `glove.6B.50d.txt` entry: 65MB instead of the 822MB archive. It verifies the
entry's CRC32 from the zip and the extracted table against a pinned SHA-256.
`GLOVE_ZIP=/path/to/glove.6B.zip` extracts from a local archive instead.

## Why the table is not committed

163MB of ASCII floats, immutable and public, reproducible byte-for-byte from a
pinned URL and hash — and above GitHub's 100MB per-file limit anyway. Git could
not delta-compress it, so every clone would carry it forever. `vectors-slice.txt`
is the committed answer instead: the words `words.yml` names, enough to re-run
the direction test whole. The analogy experiment cannot be sliced, because
ranking the entire vocabulary *is* the measurement, so its output is committed
instead of its input.
