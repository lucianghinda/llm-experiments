`count_transpositions` is at `app/services/authors/match_by_name.rb:108`. It does the third part of the Jaro score: it counts how many matched characters are in the wrong **order**.

## Input

The method runs after `count_matches` (line 91). That earlier method fills two boolean arrays:

- `matches_a[i]` — true if character `i` of `string_a` found a partner in `string_b`
- `matches_b[j]` — true if character `j` of `string_b` was used as a partner

A partner must be the same character and must be inside a window of `match_distance` positions. So the two arrays always hold the **same number** of `true` flags.

## The algorithm

```ruby
k = 0
transpositions = 0
string_a.each_char.with_index do |char, i|
  next unless matches_a[i]      # skip unmatched characters of A

  k += 1 until matches_b[k]     # move k to the next matched character of B
  transpositions += 1 if char != string_b[k]
  k += 1                        # step past it for the next round
end
transpositions / 2
```

Read it as two pointers that walk the two strings, but they see only the matched characters:

1. The loop goes through `string_a` and ignores every character that has no partner.
2. `k` is a pointer into `string_b`. The `until` line pushes `k` forward until it points at the next matched character of `string_b`.
3. Now the two pointers are at the *n*-th matched character of each string. If the characters are different, the pair is out of order — add 1.
4. Move `k` one step forward, so the next round finds the next matched character.

At the end, divide by 2. Each swapped pair produces two mismatches (one at each position), so the count is always double the real number of transpositions.

## Example: `martha` vs `marhta`

All six characters match, so both arrays are all `true`.

| i | char of A | k | char of B | result |
|---|---|---|---|---|
| 0 | m | 0 | m | same |
| 1 | a | 1 | a | same |
| 2 | r | 2 | r | same |
| 3 | **t** | 3 | **h** | mismatch → 1 |
| 4 | **h** | 4 | **t** | mismatch → 2 |
| 5 | a | 5 | a | same |

Return value: `2 / 2 = 1`. One transposition — the swapped `th`/`ht`.

`jaro_similarity` (line 86) then computes `(6/6 + 6/6 + (6-1)/6) / 3 = 0.944`.

## Two notes

- `transpositions / 2` is integer division on an `Integer`. This is correct here, because the mismatch count is always even.
- `k += 1 until matches_b[k]` has no bounds check. It is safe only because `count_matches` marks the same number of flags in both arrays, so a next `true` always exists. If that rule ever broke, `matches_b[k]` would return `nil` past the end of the array and the loop would never stop.
