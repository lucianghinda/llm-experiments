`count_transpositions` compares the matched characters from both strings in their original order.

`matches_a` and `matches_b` mark which character positions were paired by `count_matches`. The method:

1. Skips every unmatched character in `string_a`.
2. Uses `k` to find the next matched character in `string_b`.
3. Compares those two matched characters.
4. Counts a mismatch when the matched characters appear in a different order.

Finally, it divides the mismatch count by two because one transposition produces two mismatches. For example, comparing `MARTHA` with `MARHTA` finds `T/H` and `H/T` as two mismatches, which represent one transposition.
