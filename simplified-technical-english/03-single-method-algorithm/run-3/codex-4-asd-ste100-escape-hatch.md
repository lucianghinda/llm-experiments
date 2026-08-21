[`count_transpositions`](<app-root>/app/services/authors/match_by_name.rb:108) counts matched characters that appear in a different order. It is part of the Jaro similarity calculation.

The arguments `matches_a` and `matches_b` are Boolean arrays. A `true` value identifies a character that `count_matches` matched earlier.

The method works as follows:

1. `k` points to the next matched character in `string_b`.
2. The loop reads each character in `string_a`.
3. It skips a character when `matches_a[i]` is `false`.
4. It moves `k` forward until `matches_b[k]` is `true`.
5. It compares the two matched characters.
6. If the characters differ, it adds one to `transpositions`.
7. It divides the final count by two.

The division is necessary because one transposition produces two character mismatches. For example:

```text
MARTHA
MARHTA
```

The comparison finds two mismatches: `T` against `H`, and `H` against `T`. These two mismatches represent one transposition, so the result is `2 / 2 = 1`.

The method uses integer division. It also assumes that both match arrays contain the same number of `true` values. `count_matches` guarantees this because it marks one position in each array for every match.