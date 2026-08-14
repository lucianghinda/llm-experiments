The method [`count_transpositions`](app/services/authors/match_by_name.rb:108) counts matched characters that are in a different order.

- `k` stores the current position in `string_b`.
- The method reads each character in `string_a`.
- It ignores a character when `matches_a[i]` is false.
- It moves `k` to the next matched character in `string_b`.
- It compares the two matched characters.
- It adds one when the characters are different.
- It then moves to the next position in `string_b`.

One transposition causes two character differences. Therefore, the method divides the difference count by two.

For example, compare `martha` with `marhta`. The method finds two differences: `t` against `h`, and `h` against `t`. It returns `1` transposition.

The method requires `matches_a` and `matches_b` to contain the same number of matched positions.