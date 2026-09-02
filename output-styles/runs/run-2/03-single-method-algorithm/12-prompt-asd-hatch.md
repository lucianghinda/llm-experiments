## What the method does

`count_transpositions` (app/services/authors/match_by_name.rb:108) is one step of the Jaro similarity calculation at app/services/authors/match_by_name.rb:71. It counts how many matched characters are in the wrong order.

## The inputs

The method receives four values:

- `string_a` and `string_b` — the two names, in lower case.
- `matches_a` and `matches_b` — two boolean arrays. `count_matches` (app/services/authors/match_by_name.rb:91) fills these arrays. A `true` value at position `i` shows that the character at position `i` has a partner in the other string.

Both arrays contain the same number of `true` values, because `count_matches` sets one flag in each array for each match.

## The procedure

1. Set the counter `k` to 0. This counter points to a position in `string_b`.
2. Read each character of `string_a`, from the start to the end.
3. If the character is not marked in `matches_a`, ignore it and continue (app/services/authors/match_by_name.rb:112).
4. If the character is marked, move `k` forward until `matches_b[k]` is `true` (app/services/authors/match_by_name.rb:114). This finds the next matched character in `string_b`.
5. Compare the two characters. If they are different, add 1 to `transpositions` (app/services/authors/match_by_name.rb:115).
6. Move `k` forward by one position, and continue with the next character.
7. Divide the total by 2 and return the result (app/services/authors/match_by_name.rb:118).

The method compares the matched characters of `string_a` with the matched characters of `string_b`, in sequence. It ignores the unmatched characters in both strings.

## Why the division by two

Each pair of characters in the wrong order gives two differences: one at the first position, and one at the second position. The Jaro formula needs the number of *pairs*. Therefore the method divides by 2. Integer division is correct here, because the count of differences is always an even number.

## An example

The names are `martha` and `marhta`. All six characters match, so both boolean arrays contain six `true` values.

| Position | `string_a` | `string_b` | Result |
|---|---|---|---|
| 0 | m | m | same |
| 1 | a | a | same |
| 2 | r | r | same |
| 3 | t | h | different |
| 4 | h | t | different |
| 5 | a | a | same |

The count of differences is 2. The method returns `2 / 2 = 1`. One pair of characters is in the wrong order.

## How the result is used

The Jaro formula at app/services/authors/match_by_name.rb:86 uses the result in the third term: `(matches - transpositions) / matches`. More transpositions give a lower score.

`jaro_winkler` (app/services/authors/match_by_name.rb:62) then increases the score if the two names have the same first characters. `call` (app/services/authors/match_by_name.rb:18) marks an author for review when the best score is 0.85 or more.

## One safety note

Line 114 (`k += 1 until matches_b[k]`) has no boundary test. It is safe only because `matches_a` and `matches_b` always contain the same number of `true` values. If a future change breaks that condition, this loop reads past the end of the array. `matches_b[k]` then returns `nil`, the loop continues, and the method does not stop.
