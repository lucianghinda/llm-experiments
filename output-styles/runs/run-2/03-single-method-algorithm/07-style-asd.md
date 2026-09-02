## What the method does

`app/services/authors/match_by_name.rb:108` counts the transpositions for the Jaro similarity score. A transposition is a pair of characters that occur in both strings, but in a different order.

The method receives four values:

| Value | Content |
|---|---|
| `string_a`, `string_b` | The two names in lower case |
| `matches_a` | One boolean for each position in `string_a`. `true` = this character has a match |
| `matches_b` | The same booleans for `string_b` |

`count_matches` (line 91) sets these two boolean arrays before this method starts. Each match sets one flag in `matches_a` and one flag in `matches_b`. Thus the two arrays always contain the same number of `true` values.

## How the code operates

1. `k` is a cursor into `string_b`. It always points to the next matched position in `string_b`. `transpositions` is the counter.
2. The loop reads each character of `string_a` with its index `i` (line 111).
3. Line 112 rejects the characters that have no match. Only matched characters continue.
4. Line 114 moves `k` forward until it points to a matched position in `string_b`. The unmatched positions are thus removed from the comparison.
5. Line 115 compares the two matched characters. If the characters are different, the order is different. The counter increases.
6. Line 116 moves `k` one position forward for the subsequent character.
7. Line 118 divides the counter by two. Each disagreement in the order is counted two times — one time at each of the two positions. Ruby divides integers, thus the result is a whole number.

The effect is a comparison of two sub-sequences: the matched characters of `string_a` against the matched characters of `string_b`, in their original order.

## Example

Compare `martha` with `marhta`. All six characters have a match, thus both sub-sequences are complete:

```
string_a:  m a r t h a
string_b:  m a r h t a
                ^ ^
```

Position 3 gives `t` against `h`, and position 4 gives `h` against `t`. The counter becomes 2. The method returns `2 / 2 = 1`.

## The use of the result

`jaro_similarity` (line 86) uses the value in the third term of the Jaro formula:

```
(matches - transpositions) / matches
```

Thus a high number of transpositions decreases the score. Two names with the same letters in a different order get a lower score than two identical names. `jaro_winkler` (line 62) then adds a bonus for a common prefix, and `call` (line 18) compares the final score against `REVIEW_THRESHOLD` (0.85).

## One note on safety

Line 114 has no limit on `k`. If `matches_b` contained fewer `true` values than `matches_a`, `matches_b[k]` would return `nil` for each subsequent index and the loop would not stop. `count_matches` prevents this condition, because it sets the flags in pairs. The code is thus correct, but it depends on that invariant.
