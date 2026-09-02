## What the method does

`count_transpositions` (app/services/authors/match_by_name.rb:108) is a step in the Jaro similarity calculation. It counts how many matched characters are in the wrong order.

`count_matches` (app/services/authors/match_by_name.rb:91) runs first. It fills two boolean arrays:

- `matches_a[i]` is `true` when character `i` of `string_a` has a partner in `string_b`.
- `matches_b[j]` is `true` when character `j` of `string_b` is that partner.

Both arrays hold the same number of `true` values, because `count_matches` sets one flag in each array per match.

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

The method makes two lists in your mind: the matched characters of `string_a` in their sequence, and the matched characters of `string_b` in their sequence. Then it compares the two lists position by position.

1. The loop reads `string_a` from left to right. It ignores each character that has no match (`next unless matches_a[i]`).
2. The variable `k` is a pointer into `string_b`. The line `k += 1 until matches_b[k]` moves the pointer forward to the next matched character of `string_b`. It skips the unmatched characters.
3. The two characters are now at the same position in their lists. If the characters are different, the code adds 1 to `transpositions` (app/services/authors/match_by_name.rb:115).
4. The line `k += 1` moves the pointer past the character that it used. This prevents a second use of the same character.

The last line divides by 2. This is necessary because one pair of characters in the wrong order gives two differences: one at each of the two positions. The Jaro formula needs the number of pairs, not the number of differences.

## Example

Compare `martha` and `marhta`:

| Position | `string_a` | `string_b` | Result |
|---|---|---|---|
| 1 | m | m | same |
| 2 | a | a | same |
| 3 | r | r | same |
| 4 | t | h | different |
| 5 | h | t | different |
| 6 | a | a | same |

All 6 characters match, and the raw count is 2. The method returns `2 / 2 = 1`. One pair (`t` and `h`) is in the wrong order.

The caller then uses this value in the third term of the Jaro formula, `(matches - transpositions) / matches` (app/services/authors/match_by_name.rb:88). For this example, the Jaro score is 0.944, and `jaro_winkler` increases it to 0.961 because the two names have a common prefix of `mar`.

## One risk

The line `k += 1 until matches_b[k]` has no limit. If `matches_b` contained fewer `true` values than `matches_a`, `matches_b[k]` would return `nil` after the end of the array, and the loop would not stop. The code is safe today, because `count_matches` always sets the flags in pairs. But the safety comes from the other method, not from this one.
