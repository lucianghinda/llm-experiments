The method [`count_transpositions`](app/services/authors/match_by_name.rb:108) calculates the number of matched character pairs that are in a different order.

1. `k` identifies a position in `string_b`.
2. The method reads each character in `string_a`.
3. It ignores a character if `matches_a` marks the character as not matched.
4. It moves `k` to the next matched character in `string_b`.
5. It compares the two matched characters.
6. If the characters are different, it adds 1 to `transpositions`.
7. It divides the final value by 2. One transposed pair causes two character differences.

Example:

```text
string_a: MARTHA
string_b: MARHTA
```

`T` and `H` have different positions. The comparisons find two differences. The method calculates `2 / 2` and returns `1`.

The method requires `matches_a` and `matches_b` to contain valid match information from `count_matches`. Ruby uses integer division here. Thus, the result is an integer.