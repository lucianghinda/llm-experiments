Here's `count_transpositions` (`app/services/authors/match_by_name.rb:108`):

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

It's step 2 of the Jaro similarity used by `Authors::MatchByName` to fuzzy-match an incoming author name against existing `Author#name` / `Author#name_override` values (`match_by_name.rb:47-51`).

`count_matches` (`match_by_name.rb:91`) has already run and answered *"which characters in each string found a partner within the sliding window?"* — it fills two parallel boolean arrays, `matches_a` and `matches_b`. It deliberately does **not** record *which* character paired with which; it only sets flags.

`count_transpositions` answers the follow-up: *"of those matched characters, how many are in the wrong order relative to each other?"*

## Line by line

1. **`k` is a cursor into `string_b`** that only ever points at *matched* positions. It's declared outside the loop and never reset — that's the whole trick.
2. **`next unless matches_a[i]`** — unmatched characters in `a` are irrelevant; they were already penalised via the `matches / length` terms in the Jaro formula.
3. **`k += 1 until matches_b[k]`** — fast-forward `k` to the next matched position in `b`, skipping over anything unmatched.
4. **`transpositions += 1 if char != string_b[k]`** — now we're comparing the *n*-th matched character of `a` against the *n*-th matched character of `b`. If they disagree, this pair is out of order.
5. **`k += 1`** — consume that position so the next iteration moves forward.
6. **`transpositions / 2`** — each swap shows up twice (once looking from each side), so halve it.

Effectively the method extracts the two matched *subsequences* and compares them position-by-position, without ever materialising them as strings.

## Worked example — `"martha"` vs `"marhta"`

After `count_matches`, all six characters match on both sides. Walking them in order:

| n | `a`'s matched char | `b`'s matched char | mismatch? |
|---|---|---|---|
| 0 | `m` | `m` | |
| 1 | `a` | `a` | |
| 2 | `r` | `r` | |
| 3 | `t` | `h` | ✔ |
| 4 | `h` | `t` | ✔ |
| 5 | `a` | `a` | |

2 mismatches → `2 / 2` → **1 transposition**. Feeding that back into `jaro_similarity` (`match_by_name.rb:86-88`) gives `(1 + 1 + 5/6) / 3 ≈ 0.944`, and the Winkler prefix bonus for `"mar"` lifts it to ≈ `0.961` — the textbook value for this pair, which is a good sign the implementation is faithful.

`★ Insight ─────────────────────────────────────`
- **The `k` cursor is what makes this O(n) instead of O(n²).** Because both loops advance monotonically, it's a two-pointer merge over the matched positions. Rewriting it as `string_a.chars.select.with_index { |_, i| matches_a[i] }` zipped against the same for `b` would be clearer but allocates two arrays per comparison — and `find_best_fuzzy_match` calls this twice per author across a `find_each` over the whole table, so allocation pressure is real here.
- **There's a hidden coupling to `count_matches`:** `k += 1 until matches_b[k]` has no bounds check. It's only safe because `count_matches` sets exactly as many `true` flags in `matches_b` as in `matches_a`. If that invariant ever broke, `matches_b[k]` would return `nil` past the end and this would spin forever rather than raise — a silent hang instead of a loud error.
- **`transpositions / 2` is integer division, and that's intentional, not sloppy.** The canonical Jaro definition is "half the number of transpositions," floored. For a 3-cycle like matched subsequences `abc` vs `bca`, all three positions differ and `3 / 2 == 1` — Jaro genuinely under-counts there, so this matches the standard rather than fixing it.
`─────────────────────────────────────────────────`

One thing worth flagging while you're in this file: `find_best_fuzzy_match` (`match_by_name.rb:39`) loads every author and runs this pure-Ruby Jaro-Winkler on each one. Postgres ships `pg_trgm` with a `similarity()` function and a GIN index, which would push this into the database. Happy to look at that if the author table is growing.
