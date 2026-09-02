## What it does

`count_transpositions` (`app/services/authors/match_by_name.rb:108`) is the second half of the Jaro similarity formula. It counts how many matched characters are **in the wrong order**.

It does not run alone. `count_matches` (`app/services/authors/match_by_name.rb:91`) runs first and fills two boolean arrays:

- `matches_a[i]` — true if character `i` of `string_a` found a partner in `string_b`
- `matches_b[j]` — true if character `j` of `string_b` was used as a partner

Both arrays hold the same number of `true` values.

## How it works

```ruby
k = 0
transpositions = 0
string_a.each_char.with_index do |char, i|
  next unless matches_a[i]          # skip characters with no partner

  k += 1 until matches_b[k]         # move k to the next matched char in string_b
  transpositions += 1 if char != string_b[k]
  k += 1                            # step past it for the next round
end
transpositions / 2
```

The idea is to pull out the matched characters of both strings as two sub-sequences, keeping their original order, and then compare them position by position.

1. `i` walks over `string_a`. Unmatched positions are skipped (line 112).
2. `k` is a separate cursor over `string_b`. Line 114 pushes it forward until it lands on the next matched position. So the *n*-th matched character of `a` is always compared with the *n*-th matched character of `b`.
3. If the two characters differ, the pair is out of order, and the counter goes up (line 115).
4. `k += 1` (line 116) makes sure the next round starts after the character just used.
5. The result is halved (line 118). A swap always produces two mismatches — one at each end of the swap — so the raw count is double the real number of transpositions. Integer division is correct here, because the raw count is always even.

## Example

`"martha"` vs `"marhta"`. All six characters match, so both arrays are all `true`.

| position | `a` | `b` | result |
|---|---|---|---|
| 0 | m | m | same |
| 1 | a | a | same |
| 2 | r | r | same |
| 3 | t | h | mismatch |
| 4 | h | t | mismatch |
| 5 | a | a | same |

Raw count is 2, so the method returns `1`.

Back in `jaro_similarity` (line 86):

```
(6/6 + 6/6 + (6 - 1)/6) / 3 = 0.944
```

## Notes on safety

The `k += 1 until matches_b[k]` loop has no bound check. In Ruby, reading past the end of an array gives `nil`, so an overrun would loop forever. It cannot happen here: `matches_a` and `matches_b` contain the same number of `true` values by construction in `count_matches`, so `k` always finds another `true` before the array ends. The safety depends on that invariant, not on a guard in this method.
