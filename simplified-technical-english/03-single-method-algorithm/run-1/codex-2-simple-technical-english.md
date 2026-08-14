`count_transpositions` measures how many matched characters appear in a different order between two strings. It is part of the Jaro similarity calculation.

In [match_by_name.rb](app/services/authors/match_by_name.rb:108):

- `matches_a` and `matches_b` are boolean arrays marking which characters were previously matched.
- `i` moves through `string_a`.
- `k` moves through only the matched characters in `string_b`.
- For each matched character in `string_a`, it compares that character with the next matched character in `string_b`.
- If the characters differ, it records an ordering mismatch.
- It divides the mismatch count by two because one swapped pair produces two mismatches.

Example:

```text
string_a: MARTHA
string_b: MARHTA
```

The matched character sequences differ at two positions:

```text
T vs H
H vs T
```

Those two mismatches represent one transposition, so the method returns `2 / 2 = 1`.

In plain terms: it filters both strings down to their matched characters, compares their order, and counts how many character pairs have traded places.