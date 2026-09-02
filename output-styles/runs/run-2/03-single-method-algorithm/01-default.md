`count_transpositions` (`app/services/authors/match_by_name.rb:108`) is the second half of the Jaro similarity computation. It's called from `jaro_similarity` at line 84, after `count_matches` has already decided *which* characters pair up.

## What it receives

- `string_a`, `string_b` — the two downcased strings
- `matches_a`, `matches_b` — boolean arrays filled in by `count_matches:12
  - `matches_a[i] = true` → the character at `string_a[i]` found a partner in `string_b` within the sliding window
  - `matches_b[j] = true` → `string_b[j]` was consumed as somebody's partner

Crucially, `count_matches` pairs them 1:1 and only ever pairs *equal* characters, so both arrays contain exactly the same number of `true` entries, and the matched characters of `a` are a permutation of the matched characters of `b`.

## What it does

It extracts the matched characters from each string **in order** and compares them position by position:

```ruby
k = 0
string_a.each_char.with_index do |char, i|
  next unless matches_a[i]        # skip unmatched chars in a

  k += 1 until matches_b[k]       # advance k to the next matched index in b
  transpositions += 1 if char != string_b[k]
  k += 1                          # consume that position
end
```

- `i` walks every character of `string_a`; unmatched ones are skipped.
- `k` is an independent cursor into `string_b` that only ever stops on matched positions.
- So the *n*-th matched character of `a` is lined up against the *n*-th matched character of `b`. If they differ, the pair is out of sequence order → count it.

## Why divide by 2

Every genuine swap shows up twice — once when you look at it from `a`'s side and once from `b`'s. Jaro's definition of `t` is "half the number of matching characters that are in different sequence order", so `transpositions / 2` at line 118 converts the mismatch count into swaps.

## Worked example: `martha` vs `marhta`

All 6 characters match in both strings, so the ordered matched sequences are:

```
a: m a r t h a
b: m a r h t a
        ^ ^        → 2 mismatched positions
```

`transpositions = 2`, returns `1`. Feeding that back into line 86-88:

```
(6/6 + 6/6 + (6-1)/6) / 3 = 0.9444
```

which is the textbook Jaro score for that pair. `jaro_winkler` (line 62) then boosts it by the common prefix (`mar`, length 3): `0.9444 + 3 * 0.1 * (1 - 0.9444) ≈ 0.9611`.

## Two things worth knowing

1. **`transpositions / 2` is integer division and it truncates.** For permutations like `abc`/`bca` all three positions mismatch → `3 / 2 = 1`. That's the conventional Jaro implementation (every standard implementation does the same), not a bug, but it means the metric under-counts cyclic rearrangements.

2. **`k += 1 until matches_b[k]` has no bounds check.** It's safe only because `count_matches` guarantees `matches_a` and `matches_b` hold an equal number of `true`s, so `k` can never run past the last matched index. If that invariant were ever broken, `matches_b[k]` would return `nil` past the end and the loop would spin forever. Since both arrays are produced by the same private method a few lines above, the invariant holds — but it's the one line here that depends on a caller contract rather than defending itself.
