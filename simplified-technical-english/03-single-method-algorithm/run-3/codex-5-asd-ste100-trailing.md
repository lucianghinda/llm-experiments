The method [`count_transpositions`](<app-root>/app/services/authors/match_by_name.rb:108) counts matched characters that occur in a different order.

`matches_a` and `matches_b` identify the matched characters in each string. The `count_matches` method creates these two lists.

The method does these operations:

1. It reads each matched character in `string_a`.
2. It uses `k` to find the next matched character in `string_b`.
3. It compares the two characters.
4. It increases `transpositions` when the characters are different.
5. It moves `k` to the next position in `string_b`.
6. It divides the result by two.

For example:

```text
string_a: MARTHA
string_b: MARHTA
```

The matched character sequences differ at two positions:

```text
M A R T H A
M A R H T A
      ↑ ↑
```

These two differences describe one change of order. Thus, the method divides the difference count by two and returns `1`.

The division uses integers. If the difference count is odd, Ruby removes the remainder. For example, `3 / 2` returns `1`.

The Jaro similarity calculation uses this result. More transpositions produce a lower similarity score.