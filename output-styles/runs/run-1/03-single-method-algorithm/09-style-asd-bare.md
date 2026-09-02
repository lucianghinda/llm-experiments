`count_transpositions` is at `app/services/authors/match_by_name.rb:108`. It is one step of the Jaro similarity calculation (`jaro_similarity`, line 71).

## What the method receives

`count_matches` runs first (line 81). That method fills two boolean arrays:

- `matches_a[i]` is `true` if character `i` of `string_a` has a partner in `string_b`.
- `matches_b[j]` is `true` if character `j` of `string_b` has a partner in `string_a`.

Both arrays hold the same number of `true` values. Each match sets one flag in each array.

## How the method works

The method compares the matched characters of the two strings in order.

1. `k` is a cursor in `string_b`. It starts at `0`.
2. The loop reads each character of `string_a` with its index `i`.
3. If `matches_a[i]` is `false`, the loop skips that character (line 112).
4. `k += 1 until matches_b[k]` moves the cursor to the next matched position in `string_b` (line 114).
5. The method compares the two matched characters. If they are different, it adds `1` to `transpositions` (line 115).
6. `k += 1` moves the cursor past that position (line 116).

The result is `transpositions / 2` (line 118). Ruby divides integers, so the result is a whole number. The division is necessary because one swap of two characters gives two mismatches in the loop.

## Example

Compare `MARTHA` and `MARHTA`. All six characters match. The pairs are:

| `string_a` | `string_b` | Result |
|---|---|---|
| M | M | equal |
| A | A | equal |
| R | R | equal |
| T | H | different |
| H | T | different |
| A | A | equal |

The loop counts `2`. The method returns `1`.

## How the caller uses the value

Line 88 calculates `(matches - transpositions).to_f / matches`. This is one of the three terms of the Jaro score. More transpositions give a lower score.

## A note on line 114

`k += 1 until matches_b[k]` has no limit test. If `matches_b` held fewer `true` values than `matches_a`, `matches_b[k]` would return `nil` and the loop would not stop. This does not occur here, because `count_matches` always sets the two flags together.
