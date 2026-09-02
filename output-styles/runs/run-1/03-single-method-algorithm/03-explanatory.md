## What it is

`count_transpositions` is the second half of a hand-rolled **Jaro similarity** implementation. The service uses it to fuzzy-match an incoming author name against `Author#name` / `Author#name_override`, scoring ≥ `REVIEW_THRESHOLD` (0.85) to flag a human-review candidate (`app/services/authors/match_by_name.rb:25`).

```ruby
def count_transpositions(string_a, string_b, matches_a, matches_b)
  k = 0
  transpositions = 0
  string_a.each_char.with_index do |char, i|
    next unless matches_a[i]

    k += 1 until matches_b[k]
    transpositions += 1 if char != string_b[k]
    k += 1
  end
  transpositions / 2
end
```

## The precondition it relies on

It never runs alone. `count_matches` (`:91`) runs first and **mutates** the two boolean arrays passed into it. `matches_a[i]` is `true` when character `i` of A found a partner in B within the sliding window `match_distance`; `matches_b[j]` is `true` for that partner. Because each successful pairing sets exactly one flag in each array and then `break`s, the two arrays are guaranteed to hold **the same number of `true`s**.

That invariant is the whole basis of this method: you can walk the matched characters of A in order and the matched characters of B in order, and they line up one-to-one.

## The walkthrough

- `k` is a cursor into `string_b` that is declared **outside** the loop and only ever moves forward. It's never reset. That's what makes this O(n) instead of O(n²).
- `next unless matches_a[i]` — unmatched characters in A are irrelevant; only the matched subsequence participates.
- `k += 1 until matches_b[k]` — fast-forward `k` to the next *matched* position in B, skipping B's unmatched characters. If `matches_b[k]` is already true, the loop body never executes and `k` stays put.
- `transpositions += 1 if char != string_b[k]` — we now have the n-th matched char of A next to the n-th matched char of B. If they differ, the two strings contain the same characters but in a different relative order → a half-transposition.
- `k += 1` consumes that position so the next iteration starts past it.

## Why `/ 2`

A genuine swap gets counted twice. Take `"martha"` vs `"marhta"` — all six characters match on both sides, so the matched subsequences are `martha` and `marhta`:

| i | A char | k | B char | mismatch? |
|---|--------|---|--------|-----------|
| 0 | m | 0 | m | no |
| 1 | a | 1 | a | no |
| 2 | r | 2 | r | no |
| 3 | **t** | 3 | **h** | yes |
| 4 | **h** | 4 | **t** | yes |
| 5 | a | 5 | a | no |

Two mismatched positions, one swapped pair → `2 / 2 = 1`. Feeding that back into `jaro_similarity` (`:86`) gives `(6/6 + 6/6 + 5/6) / 3 ≈ 0.9444`, and `jaro_winkler` bumps it to ≈ `0.9611` on the 3-char shared prefix `mar` — the textbook values for that pair.

`★ Insight ─────────────────────────────────────`
- **The out-param style is deliberate, not sloppy.** `matches_a`/`matches_b` are allocated in `jaro_similarity` (`:78-79`), filled by `count_matches`, then *read* by `count_transpositions`. Splitting the algorithm into two passes over shared state is what keeps each method under ten lines instead of one 40-line blob.
- **`count_transpositions` doesn't take `match_distance`.** Windowing is entirely `count_matches`' job; by the time we get here, "which characters matched" is already settled and only *order* is in question.
- **Comparison is case-insensitive by the time it lands here.** `jaro_winkler` (`:65`) downcases both strings before calling `jaro_similarity`, so `count_transpositions` compares already-normalised characters — relevant for author names like `"DHH"` vs `"dhh"`.
`─────────────────────────────────────────────────`

## Two sharp edges worth knowing

**1. `k += 1 until matches_b[k]` has no bounds check.** In Ruby, indexing past the end of an array returns `nil`, which is falsy — so if `matches_a` ever had more `true`s than `matches_b`, this becomes an infinite loop incrementing `k` forever. It's safe only because `count_matches` maintains the equal-count invariant. `jaro_similarity`'s `return 0.0 if matches == 0` guard (`:82`) covers the empty case separately.

**2. Integer division truncates on odd mismatch counts.** For a 3-cycle like `"abc"` vs `"bca"` (every position mismatches), you get `3 / 2 = 1` rather than 1.5. This matches the standard reference implementations of Jaro, so it's consistent with what you'd get from a gem — just be aware the "transposition count" is a floor, not an exact rearrangement cost.

## Where it sits in the scoring pipeline

`call` → `find_exact_match` (SQL, case-insensitive, score 1.0) → if no hit, `find_best_fuzzy_match` iterates **every** author with `find_each`, computing `jaro_winkler` in Ruby against both `name` and `name_override` and taking the max. `count_transpositions` is therefore invoked twice per author per lookup — an O(authors × name_length²)-ish scan in application memory rather than the database. Fine for a few thousand authors; something to watch if that table grows or if `MatchByName` ever gets called inside a per-record import loop.
