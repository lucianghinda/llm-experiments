Here's the method, at `app/services/authors/match_by_name.rb:108`:

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

## What it's for

This is step 2 of the Jaro similarity calculation. Step 1 (`count_matches`, line 91) already answered *"which characters appear in both strings, close enough together to count?"* — it flipped flags in the `matches_a` / `matches_b` boolean arrays. But matching alone doesn't tell you whether those characters appear in the **same order**. `count_transpositions` measures that ordering penalty.

## How it works, line by line

The core idea: **extract the matched characters from each string, in order, and compare them pairwise.**

- `string_a.each_char.with_index` walks every character of `a`, but `next unless matches_a[i]` skips any character that wasn't matched. So the loop body only runs for the matched subsequence of `a`.
- `k` is a cursor into `string_b`. The line `k += 1 until matches_b[k]` fast-forwards it to the *next matched position in b*, skipping over unmatched characters.
- At that point you're comparing the *n*-th matched char of `a` against the *n*-th matched char of `b`. If they differ, the characters are out of order relative to each other → `transpositions += 1`.
- `k += 1` moves past the position just consumed so the next iteration finds the following match.

## Why divide by 2

A swap is inherently symmetric: if `t` sits where `h` should be, then `h` also sits where `t` should be. The loop counts **both** halves, so the raw count is always even, and `transpositions / 2` converts "mismatched positions" into "actual swaps." Integer division is safe precisely because the sum can never be odd.

## Worked example: `"martha"` vs `"marhta"`

All 6 characters match, so every flag in both arrays is `true` and `k` tracks `i` exactly:

| i | char in a | b[k] | mismatch? |
|---|---|---|---|
| 0 | m | m | no |
| 1 | a | a | no |
| 2 | r | r | no |
| 3 | **t** | **h** | ✓ |
| 4 | **h** | **t** | ✓ |
| 5 | a | a | no |

Raw count = 2 → returns `1`. Feeding that back into line 86:

```
(6/6 + 6/6 + (6-1)/6) / 3 = 0.9444
```

and then `jaro_winkler` boosts it for the 3-character shared prefix `"mar"`: `0.9444 + 3 × 0.1 × (1 - 0.9444) = 0.9611`. That clears `REVIEW_THRESHOLD` (0.85), so this pair would be flagged as a `:review` result rather than auto-matched.

`★ Insight ─────────────────────────────────────`
- **`matches_a`/`matches_b` are out-parameters.** `count_matches` (line 91) mutates the arrays it's handed rather than returning them, and `jaro_similarity` allocates them at lines 78–79 so both helpers can share state. That's a C-flavored idiom, unusual in Ruby — the alternative (returning two arrays plus a count) would avoid the hidden coupling, but the two methods are only ever called as a pair from line 81/84.
- **`k += 1 until matches_b[k]` has no bounds check, and that's provably fine.** `count_matches` sets exactly one `true` in `matches_b` for every `true` it sets in `matches_a`, so the matched counts are equal and `k` can never overrun. If those counts could ever diverge, indexing past the end would return `nil` forever and the `until` would spin infinitely — this loop's safety rests entirely on an invariant established in a *different* method.
- **This service pays a real cost for its purity.** `find_best_fuzzy_match` (line 47) runs `find_each` over every author and computes this pure-Ruby Jaro-Winkler twice per row. PostgreSQL ships `pg_trgm` with a `similarity()` function that would push this into an indexed query — worth knowing if the authors table grows.
`─────────────────────────────────────────────────`
