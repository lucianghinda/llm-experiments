[`count_transpositions`](app/services/authors/match_by_name.rb:108) measures how many matched characters appear in a different order.

It works like this:

1. `matches_a` and `matches_b` identify which character positions were matched earlier.
2. It walks through the matched characters in `string_a`.
3. `k` points to the next matched character in `string_b`, skipping unmatched positions.
4. If the two matched characters differ, it records one ordering mismatch.
5. It divides the mismatch count by two because one swapped pair normally creates two mismatches.

For example:

```text
string_a: martha
string_b: marhta
```

The matched sequences differ twice:

```text
m a r t h a
m a r h t a
      ↑ ↑
```

Those two mismatches represent one swap, so the method returns `2 / 2 = 1`.

One Ruby detail: `/ 2` performs integer division here. If the mismatch count is odd, the result is rounded down. The returned number is then used by `jaro_similarity` to reduce the name-similarity score.