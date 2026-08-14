`count_transpositions` counts matched characters that occur in a different order.

- `matches_a` marks the matched positions in `string_a`.
- `matches_b` marks the matched positions in `string_b`.
- `k` identifies the current matched position in `string_b`.
- The method ignores each unmarked character in `string_a`.
- For each marked character, the method finds the next marked character in `string_b`.
- It compares the two characters.
- If the characters are different, it adds 1 to `transpositions`.

One transposition causes two different comparisons. For example, `ABC` and `ACB` give two differences: `B` against `C`, and `C` against `B`. Therefore, the method divides the difference count by 2. In this example, it returns `1`.

The caller must mark the same number of positions in both match arrays.
