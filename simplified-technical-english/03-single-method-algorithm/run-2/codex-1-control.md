[`count_transpositions`](app/services/authors/match_by_name.rb:108) calculates the transposition component of the Jaro similarity score.

It receives two boolean arrays from `count_matches`:

- `matches_a[i]` indicates that character `i` in `string_a` was matched.
- `matches_b[k]` does the same for `string_b`.

The method then:

1. Iterates over the matched characters in `string_a`.
2. Uses `k` to find the next matched character in `string_b`:
   ```ruby
   k += 1 until matches_b[k]
   ```
3. Compares those two matched characters. If they differ, their ordering changed:
   ```ruby
   transpositions += 1 if char != string_b[k]
   ```
4. Advances `k` so each matched character in `string_b` is used once.
5. Divides the mismatch count by two:
   ```ruby
   transpositions / 2
   ```

The division is necessary because one swap normally produces two out-of-order comparisons. For example:

```text
MARTHA
MARHTA
```

The matched sequences differ at `T/H` and `H/T`, producing two mismatches. Dividing by two gives one transposition.

So the method doesn’t determine which characters match—that happens in `count_matches`. It compares the order of those matches, and the resulting count reduces the Jaro score. One implementation detail is that `/ 2` performs integer division here, so any fractional half is discarded.