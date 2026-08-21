[`count_transpositions`](<app-root>/app/services/authors/match_by_name.rb:108) counts matched characters that occur in a different order.

It works as follows:

1. `k` stores the current position in `string_b`.
2. The method reads `string_a` from left to right.
3. It ignores each character that is not marked in `matches_a`.
4. It moves `k` to the next matched character in `string_b`.
5. It compares the two matched characters.
6. If the characters are different, it adds one to `transpositions`.
7. It divides the final count by two.

The division is necessary because one exchanged pair causes two differences.

Example:

```text
string_a: A B C
string_b: A C B
```

The comparisons are:

```text
A = A
B ≠ C
C ≠ B
```

The method counts two differences. It returns `2 / 2`, which is one transposition.

The method does not find the matching characters. `count_matches` does that first and supplies `matches_a` and `matches_b`.