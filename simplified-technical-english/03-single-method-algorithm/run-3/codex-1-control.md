[`count_transpositions`](<app-root>/app/services/authors/match_by_name.rb:108) measures how many already-matched characters appear in a different order between two strings.

It works like this:

1. `matches_a` and `matches_b` identify character positions previously matched by `count_matches`.
2. It walks through matched characters in `string_a`.
3. `k` advances to the next matched position in `string_b`:
   ```ruby
   k += 1 until matches_b[k]
   ```
4. It compares those two matched characters. If they differ, their ordering is considered mismatched.
5. It divides the mismatch count by two because one transposition normally creates two mismatched positions.

For example:

```text
string_a: MARTHA
string_b: MARHTA
```

The matched sequences differ at two positions:

```text
M A R T H A
M A R H T A
      ↑ ↑
```

That produces `2 / 2 = 1` transposition.

The resulting number feeds into the Jaro similarity formula at [line 84](<app-root>/app/services/authors/match_by_name.rb:84). More transpositions lower the similarity score. Because this uses Ruby integer division, an odd mismatch count is rounded down.