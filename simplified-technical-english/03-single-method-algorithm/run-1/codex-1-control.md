[`count_transpositions`](app/services/authors/match_by_name.rb:108) calculates the transposition component of the Jaro string-similarity algorithm.

It works like this:

1. It scans `string_a`, skipping positions not marked as matches in `matches_a`.
2. For each matched character, `k` advances to the next matched position in `string_b`, using `matches_b`.
3. It compares those two matched characters. If they differ, it records an ordering mismatch.
4. It divides the mismatch count by two because one swapped pair produces two mismatches.

For example:

```text
MARTHA
MARHTA
```

The matched sequences disagree twice—`T` versus `H`, then `H` versus `T`—so the method returns `2 / 2 = 1` transposition.

The important distinction is that this does not calculate the minimum number of arbitrary swaps. It measures how many already-matched characters appear out of order, as required by Jaro similarity. The preceding `count_matches` method constructs the `matches_a` and `matches_b` marker arrays using Jaro’s matching window. Ruby performs integer division here, so the result is an integer.