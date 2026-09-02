`count_transpositions` is at `app/services/authors/match_by_name.rb:108`.

## What it is for

It is one step of the Jaro similarity score. Before it runs, `count_matches` (line 91) has already filled two boolean arrays:

- `matches_a[i]` is `true` if character `i` of `string_a` found a partner in `string_b`.
- `matches_b[j]` is `true` if character `j` of `string_b` was used as such a partner.

Both arrays contain the **same number** of `true` values, because every match sets one flag in each.

`count_transpositions` answers a different question: the matched characters exist in both strings, but are they in the **same order**?

## How it works

```ruby
k = 0
transpositions = 0
string_a.each_char.with_index do |char, i|
  next unless matches_a[i]

  k += 1 until matches_b[k]
  transpositions += 1 if char != string_b[k]
  k += 1
end
transpositions / 2
```

1. `k` is a cursor into `string_b`. It remembers where the previous matched character of `b` was.
2. The loop walks `string_a` from left to right. `next unless matches_a[i]` skips every character that did not match, so only matched characters are processed.
3. `k += 1 until matches_b[k]` moves the cursor forward until it lands on the next matched character in `b`.
4. At this point the code has a **pair**: the *n*-th matched character of `a` and the *n*-th matched character of `b`. If those two characters are not equal, the order is different, so `transpositions` grows by one.
5. `k += 1` steps past the position just used, so the next round finds the following match instead of the same one.
6. `transpositions / 2` is the return value. Two characters that are swapped always produce **two** disagreeing pairs, so the raw count is double the real number of swaps. Integer division halves it.

## Example

`"MARTHA"` versus `"MARHTA"`. All six characters match, so the two matched sequences are:

| position | a | b | equal? |
|---|---|---|---|
| 1 | M | M | yes |
| 2 | A | A | yes |
| 3 | R | R | yes |
| 4 | T | H | **no** |
| 5 | H | T | **no** |
| 6 | A | A | yes |

Raw count is `2`, and `2 / 2` returns `1` transposition. Line 88 then uses it in `(matches - transpositions) / matches`, which lowers the score because the letters are in the wrong order.

## Two things worth knowing

- The method compares two sequences position by position. It does not compute the true minimum number of swaps. That is the standard Jaro definition, not a bug.
- `k += 1 until matches_b[k]` has no upper bound check. It is safe only because `matches_a` and `matches_b` always hold an equal count of `true` values, so an *n*-th match in `b` is guaranteed to exist. If that invariant were ever broken, `matches_b[k]` would return `nil` past the end of the array and the loop would never stop.
