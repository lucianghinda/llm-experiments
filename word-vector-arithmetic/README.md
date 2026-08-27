# Does "king - man + woman = queen" hold when you check it yourself?

**Status: run on two models. 18 analogies, 15 Ruby-programming analogies and 30
held-out plural pairs, on GloVe 50d and on GPT-2's own embedding matrix. Tables
in [`results/tables.md`](results/tables.md).**

The short version, four findings.

**The famous analogy is a hit only under a convention nobody mentions:** the
three input words are removed from the results first. Keep them in and the
nearest point to `woman - man + king` is **king**. On GloVe, top-1 falls from
11/18 to 8/18 when the inputs stay in the running.

**GPT-2 is much better at the arithmetic and much worse at leaving its inputs
behind.** Its embedding matrix answers 16/18 against GloVe's 11/18 — including
every case GloVe fumbled, like `longer - long + short`, which GloVe put at rank
82. But with the inputs left in, GPT-2 drops to 5/18, and in 13 of 18 the
nearest point is one of the input words. When GPT-2 is wrong, it is *never*
wrong in an interesting way: "something else" is 0/18.

**Ruby analogies are a corpus test, and the two models fail it three orders of
magnitude apart.** A separate group — `rails - ruby + python → django`,
`gem - ruby + python → pip`, `if:unless :: while:until` — goes 0/15 on GloVe
and 0/12 on GPT-2 at top-1. But GloVe answers from the everyday senses of the
words (`sinatra - ruby + python` returns `tunes`, with `flask` at rank 274,369;
`subclass - class + parent` returns `cephalopod`, because its subclasses are
taxonomic) while GPT-2 misses to adjacent programming words: `pip` at cosine
rank 4, `npm` at 16, `until` at 7. And GPT-2's wins stop exactly where English
stops: it finds `until` and `size` but not the pure Ruby alias pairs — `inject`
sits at rank 3,893 and `filter` at 4,728, because nothing outside Ruby's
`Enumerable` links `reduce` to `inject`. The senses of programming words made
it into the embedding; the API structure did not.

**The direction claim holds on both.** A single direction from `cats - cat`
separates plural from singular on 29 of 30 GloVe pairs and 26 of 27 GPT-2 pairs
it never saw, irregular plurals included. On GPT-2, averaging five training
directions instead makes it 27/27.

This is a Ruby replication of the two word-vector demos in Grant Sanderson's
[Visualizing transformers and attention](https://www.youtube.com/watch?v=KJtZARuO3JY)
talk, whose manim source is
[`_2024/transformers/embedding.py`](https://github.com/3b1b/videos/blob/master/_2024/transformers/embedding.py),
extended to ask the question the talk leaves open.

## The question

Two claims are made about embedding spaces, and they are usually presented as
one claim.

1. **Analogy arithmetic.** `b - a + c` lands on the word that completes the
   analogy: `woman - man + king` lands on `queen`.
2. **Directions carry meaning.** The difference between one pair of words is a
   reusable direction that scores other words on the same property.

The first is the famous one and the weaker one. The second is the one that
actually generalises. Separating them is the first half of this experiment.

The second half is a gap in the talk itself. It explains GPT-3's embedding
matrix and then demonstrates on GloVe, a different object trained on a different
objective. So: do the demos survive the substitution?

## The design

**Two models, one item list.** Every number below comes from the same
`words.yml`, so nothing about the questions differs between models.

| | GloVe 6B 50d | GPT-2 |
|---|---|---|
| entries | 400,000 words | 50,257 tokens |
| dimensions | 50 | 768 |
| trained to | predict co-occurrence counts | predict the next token |
| used by the talk | yes, this is `glove-wiki-gigaword-50` | no, but its claims are about models like it |

**Analogies.** 18 quadruples over 5 relations (gender, capital, comparative,
past tense, plural). For each, compute `b - a + c` and rank the vocabulary
against it, twice: once with `a`, `b`, `c` still in the running, once with them
excluded. Recording both is the whole experiment. `gensim`'s `most_similar`
drops them silently; the `find_nearest_words` helper in the manim source does
not. Ranking uses Euclidean distance — matching the source's
`((data - vector)**2).sum(1)` — and cosine.

**The Ruby group.** 15 more quadruples, marked `group: ruby` in `words.yml` and
never mixed into the numbers above, because they ask a different question. The
original relations use everyday words in their everyday senses; these require
the programming sense of polysemous words — `rails` the framework, not the
tracks; `gem` the package, not the jewel; `hash` the data structure, not the
browns. GloVe's news-and-Wikipedia corpus (2014) barely contains those senses;
GPT-2's WebText is full of them. Same arithmetic, same scoring, different
question: does the analogy structure exist for a *domain* the corpus may not
cover?

Nine are ecosystem relations: language→framework
(`ruby:rails :: python:django`, `:: sinatra:flask`), language→package-manager
(`ruby:gem :: python:pip`, `:: javascript:npm`), collection→accessor
(`array:index :: hash:key`), Ruby-term→Python-term
(`hash:dictionary :: array:list`), exception keywords
(`raise:rescue :: throw:catch`) and project→creator
(`linux:torvalds :: ruby:matz`, `:: python:guido`).

Six are language mechanics, and three of those are a graded probe. The
mechanics: Ruby's negated keywords (`if:unless :: while:until`), what exits
what (`loop:break :: method:return`), and the inheritance hierarchy said two
ways (`class:subclass :: parent:child`). The probe is the alias relation
`map:collect :: X`: for `select:filter` and `length:size` English already
treats the pair as near-synonyms, but nothing outside Ruby's `Enumerable`
connects `reduce` to `inject` — injections are medical everywhere else. If
`inject` ranks well, the signal can only have come from code.

Vocabulary decided the item list before any vector was read: `eigenclass`,
`metaclass`, `rubygems` and `laravel` have no entry in either model, so the
most Ruby-flavoured analogies cannot be asked at all. `matz`, `guido`,
`torvalds` and `sinatra` exist in GloVe (mostly as other people: Frank Sinatra)
but have no single GPT-2 token, so three quadruples run on GloVe alone and the
report marks them rather than dropping them.

GPT-2 gets a third ranking, restricted to **word-like tokens** (32,064 of
50,257: a leading space then letters). Most of its vocabulary is fragments and
punctuation that no GloVe ranking could ever have returned, so ranking against
all of it and ranking against words are different questions.

**The plural direction.** Take `cats - cat` as a candidate direction, then score
30 held-out pairs: does the plural score above the singular? The direction is
either that single seed pair (what the talk does) or the mean of 5 separate
training pairs. The score is either a raw dot product (what the talk does) or
cosine, which removes vector length. Half the test pairs are irregular —
`man/men`, `mouse/mice`, `criterion/criteria` — because a direction built from
`cats - cat` might only be detecting a trailing `s`.

No pair is reused: the seed is in neither list, and the 5 training pairs are
disjoint from the 30 test pairs.

## What the numbers say

### The analogy is weaker than its reputation, on both models

| model | metric | inputs excluded | inputs kept |
|---|---|---|---|
| glove | euclidean | 11/18 (61%) | 8/18 (44%) |
| glove | cosine | 12/18 (67%) | 8/18 (44%) |
| gpt2 | euclidean | 16/18 (89%) | 5/18 (28%) |
| gpt2 | cosine | 16/18 (89%) | 5/18 (28%) |

`woman - man + king` has `queen` at rank 1 once `king` is removed, and `king` at
rank 1 when it is not — on both models. The arithmetic points in the right
direction without travelling far enough to leave its own inputs behind, and on
GPT-2 that is *more* true, not less:

| model | nearest point is an input | is the expected word | is something else |
|---|---|---|---|
| glove | 6/18 (33%) | 8/18 (44%) | 4/18 (22%) |
| gpt2 | 13/18 (72%) | 5/18 (28%) | 0/18 (0%) |

### GPT-2 wins everywhere except capitals

| relation | glove | gpt2 |
|---|---|---|
| gender | 3/5 (60%) | 5/5 (100%) |
| comparative | 1/3 (33%) | 3/3 (100%) |
| past-tense | 2/3 (67%) | 3/3 (100%) |
| plural | 2/3 (67%) | 3/3 (100%) |
| capital | 3/4 (75%) | 2/4 (50%) |

The GloVe misses are the interesting ones to read: `longer - long + short`
returns `actually` with `shorter` at rank 82, and `bigger - big + small` prefers
`larger` to `smaller` — the right relation applied to the wrong end of the pair.
GPT-2 gets all of those. Where GPT-2 slips is geography: `paris - france +
italy` answers `" Italian"` with `" Rome"` at rank 2, and `paris - france +
spain` answers `" Barcelona"` with `" Madrid"` at rank 2. Both times the answer
is in the right city-sized neighbourhood and loses to a near neighbour.

Restricting GPT-2's candidates to word-like tokens changed nothing (16/18 either
way). Its embedding arithmetic does not land on fragments.

### The Ruby group: zero hits, and the misses are the result

| relation | arithmetic | expected | glove top-1 | rank | gpt2 top-1 | rank |
|---|---|---|---|---|---|---|
| framework | rails - ruby + python | django | `"externally"` | 104588 | `" rail"` | 2586 |
| framework | sinatra - ruby + python | flask | `"tunes"` | 274369 | - | - |
| package | gem - ruby + python | pip | `"toolchain"` | 68835 | `" Python"` | 54 |
| package | gem - ruby + javascript | npm | `"compiler"` | 110357 | `" JavaScript"` | 87 |
| accessor | index - array + hash | key | `"benchmark"` | 19682 | `" Index"` | 608 |
| data-structure | dictionary - hash + array | list | `"contemporary"` | 1803 | `" Dictionary"` | 15 |
| error-handling | rescue - raise + throw | catch | `"blew"` | 72 | `" throwing"` | 417 |
| creator | torvalds - linux + ruby | matz | `"susumu"` | 94588 | - | - |
| creator | torvalds - linux + python | guido | `"gitai"` | 150497 | - | - |
| negated-keyword | unless - if + while | until | `"bringing"` | 980 | `" whilst"` | 7 |
| alias | collect - map + reduce | inject | `"payments"` | 124 | `" collecting"` | 3893 |
| alias | collect - map + select | filter | `"receive"` | 50712 | `" Select"` | 4728 |
| alias | collect - map + length | size | `"amount"` | 673 | `" Length"` | 16 |
| exit-keyword | break - loop + method | return | `"quick"` | 136 | `" methods"` | 160 |
| hierarchy | subclass - class + parent | child | `"cephalopod"` | 352919 | `"Parent"` | 124 |

(Euclidean, inputs excluded.) Neither model gets a single top-1, so the number
that matters is *where* the expected word landed, and there the models are
different experiments. GloVe's answers say which sense each word resolved to:
`sinatra - ruby + python` returns `tunes`, `jukebox`, `manilow`; `collect` is
money (`payments`, `costs`, `compensate`); and `subclass - class + parent`
returns `cephalopod`, `megapode` and `suborder`, because GloVe's subclasses
are taxonomic — `child` lands at rank 352,919 of 400,000. In that space the
programming relations do not exist.

GPT-2 misses to programming words adjacent to the answer: `gem - ruby +
python` puts `" Python"` first with `pip` at cosine rank 4, and — a tell that
both senses coexist in the vector — `" snake"` in the euclidean top-5. `pip`
at rank 4, `npm` at 16, `until` at 7 out of 50,257 is the same shape as the
original finding: the arithmetic points into the right neighbourhood and stops
short, this time without even the excuse of the inputs being in the way.

The alias probe draws the boundary of what GPT-2's embedding learned. Of the
three `map:collect :: X` items, it does well exactly where English helps —
`size` at rank 16, since length and size are synonyms anyway — and fails where
only Ruby's `Enumerable` supplies the link: `inject` at rank 3,893, `filter`
at 4,728, both behind plain morphology like `" collecting"` and `" Select"`.
The *senses* of programming words are in the embedding; API structure — which
method is an alias of which — is not, at least not at the input-embedding
layer.

The exceptions run the other way too. `rescue - raise + throw → catch` is the
one item GloVe does better on (72 vs 417) — the one whose relation holds in
everyday English, where things are raised and thrown, caught and rescued.
Corpus coverage, not arithmetic, is what separates the two columns.

### The direction generalises on both, and not because of spelling

| model | direction | all pairs | regular | irregular |
|---|---|---|---|---|
| glove | seed (`cats - cat`) | 29/30 (97%) | 14/15 (93%) | 15/15 (100%) |
| glove | averaged (5 pairs) | 29/30 (97%) | 14/15 (93%) | 15/15 (100%) |
| gpt2 | seed (`cats - cat`) | 26/27 (96%) | 15/15 (100%) | 11/12 (92%) |
| gpt2 | averaged (5 pairs) | **27/27 (100%)** | 15/15 (100%) | 12/12 (100%) |

Irregular plurals score as well as regular ones, so the direction is not
detecting a trailing `s`. Each model fails on exactly one pair and they are
different pairs: GloVe on **leaf / leaves**, in every condition, most likely
polysemy — it is uncased and untagged, so `leaves` carries the verb "he leaves"
in the same vector. GPT-2 on **criterion / criteria**, and only with the
single-pair seed direction; averaging five directions fixes it.

Cosine agreed with the raw dot product on every pair of both models, which is
mild evidence that the separation is about direction and not about frequent
words having longer vectors.

On the 27 pairs both models can answer, GloVe scores 26/27 in every condition
and GPT-2 26/27 seeded, 27/27 averaged.

### A methodological result: which token you pick decides the answer

GPT-2 has no `" rome"` token. It has `"rome"` — the fragment inside "Jerome"
and "chrome" — and `" Rome"`. The first version of the word-to-token policy
preferred lowercase over capitalised, picked the fragment, and the Italy
analogy answered `" Italian"` with `" Rome"` at **rank 42,047**. Reordering the
policy to prefer both mid-sentence forms over either line-initial one moved the
same word to **rank 2**, with no other change.

That is a four-order-of-magnitude swing produced by a lookup convention, not by
the model. Every result now records the token it used, and
[`results/tables.md`](results/tables.md) lists every word that resolved to
something other than its plain mid-sentence form.

Four words have no single GPT-2 token at all — `cactus`, `cacti`, `geese`,
`oxen` — so three plural pairs exist for GloVe and not for GPT-2. The comparison
tables intersect the item lists rather than compare 30 against 27.

## Caveats

- **This is not a controlled comparison.** GPT-2 differs from GloVe in
  dimensions (768 vs 50), vocabulary (tokens vs words), training objective
  (next-token vs co-occurrence) and corpus, all at once. The 16/18 against 11/18
  is real, and nothing here can say which of those four differences produced it.
  Most likely 768 dimensions is doing much of the work.
- **GPT-2 is still not GPT-3, and neither is a transformer's internals.** This
  is the input embedding matrix, before a single attention block. It is what the
  talk describes at that point, not what the model computes later.
- **The Ruby group's expected answers are judgment calls.** `gem - ruby +
  python` is scored against `pip`, but `easy_install` was the contemporary of
  GloVe's corpus and "package" is a defensible answer too. The ranks are exact;
  what counts as *the* correct fourth word is an editorial choice, which is why
  the per-item table shows what actually came first instead of only a score.
  And the two models answer different subsets — 15 items for GloVe, 12 for
  GPT-2 — because four words have vectors in only one model.
- **18, 15 and 30 are small.** These are illustrative counts on hand-picked words,
  not a benchmark, and there is no significance test. The exclusion effect is not
  a sample estimate — it is a deterministic property of the same items scored two
  ways, which is why it is reported as a count and not an interval.
- **The analogy set is easy on purpose.** Relations were chosen because they are
  the ones usually claimed to work, so these are ceilings, not averages over
  English. The Ruby group is the deliberate opposite — items nobody claims work
  — which is another reason the two are never averaged together.
- **Ties resolve in the expected word's favour.** `rank_of` counts strictly
  closer entries. Exact float ties are vanishingly rare; the choice is documented
  rather than relied on.
- **The GPT-2 word-to-token policy is an assumption**, as the rank-42,047 result
  above shows. A different policy is a different experiment.

## Layout

```
words.yml                 Every word both experiments touch. Nothing is hardcoded in a script.
vectors-slice.txt         The 116 GloVe rows words.yml names, copied verbatim (49KB).
vectors-slice-gpt2.f32    The 112 GPT-2 rows, copied as source bytes (336KB).
vectors-slice-gpt2.json   The token strings beside those rows.
scripts/fetch.rb          Pulls only the 50d entry out of glove.6B.zip, via HTTP Range.
scripts/fetch_gpt2.rb     Pulls only wte.weight out of GPT-2's safetensors, the same way.
scripts/lib/byte_source.rb  Range reads over HTTP or a local file. Shared by both fetchers.
scripts/lib/vectors.rb    Table, vector arithmetic, whole-vocabulary ranking. Stdlib only.
scripts/lib/gpt2.rb       Byte-level BPE decoding and the word-to-token policy.
scripts/lib/models.rb     One place that decides what a model is and where its files live.
scripts/slice.rb          Cuts the committed slices out of the full tables.
scripts/run.rb            Runs both experiments against one model. Measures, does not judge.
scripts/report.rb         Turns results/*.json into results/tables.md.
results/analogy-*.json    Per-analogy ranks, both metrics, every exclusion setting.
results/direction-*.json  Per-pair scores, both directions, both metrics.
results/tables.md         Generated. Every number quoted above comes from here.
data/                     Gitignored. 163MB of GloVe, 147MB of GPT-2.
```

## Running it

Without any download — reproduces the committed direction results from the
slices, and fails loudly if they disagree:

```
ruby word-vector-arithmetic/scripts/run.rb --slice --model glove
ruby word-vector-arithmetic/scripts/run.rb --slice --model gpt2
```

The whole thing:

```
ruby word-vector-arithmetic/scripts/fetch.rb                  # 65MB over the wire, ~26s
ruby word-vector-arithmetic/scripts/fetch_gpt2.rb             # 147MB, ~64s
ruby word-vector-arithmetic/scripts/run.rb --model glove      # ~49s
ruby word-vector-arithmetic/scripts/run.rb --model gpt2       # ~63s
ruby word-vector-arithmetic/scripts/slice.rb --model glove    # refresh the committed slices
ruby word-vector-arithmetic/scripts/slice.rb --model gpt2
ruby word-vector-arithmetic/scripts/report.rb                 # regenerate results/tables.md
```

Both fetchers ask for a byte range instead of a file. `fetch.rb` reads the zip's
central directory and requests just the `glove.6B.50d.txt` entry: 65MB instead
of an 822MB archive, CRC32-checked against the zip and SHA-256 against a pinned
hash. `fetch_gpt2.rb` reads the safetensors JSON header and requests just
`wte.weight`: 147MB instead of 522MB, and the other 160 tensors never cross the
network. `GLOVE_ZIP=/path/to/glove.6B.zip` extracts from a local archive.

## Why the tables are not committed

163MB and 147MB, immutable and public, reproducible byte-for-byte from pinned
URLs and hashes — and the GloVe table is above GitHub's 100MB per-file limit
anyway. Git could not delta-compress either, so every clone would carry them
forever. The slices are the committed answer instead: the rows `words.yml`
names, enough to re-run the direction test whole on either model. The analogy
experiment cannot be sliced, because ranking the entire vocabulary *is* the
measurement, so its output is committed instead of its input.
