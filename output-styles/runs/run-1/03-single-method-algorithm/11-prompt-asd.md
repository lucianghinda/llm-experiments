MCP tools weren't available (the CLI fallback was denied), so this comes from a direct read of `app/services/authors/match_by_name.rb:108`.

# `count_transpositions` — description in Simplified Technical English

## Function

The method counts the character pairs that are not in the same sequence. It is a part of the Jaro similarity calculation in `jaro_similarity` (line 84).

## The data that the method receives

- `string_a` and `string_b` — the two names, in lowercase letters.
- `matches_a` and `matches_b` — two arrays of true/false values. A `true` value shows that the character at that position has a match in the other string.

The method `count_matches` (line 91) fills the two arrays before this method starts.

## Operation

1. The method sets `k` to 0. The value `k` is a position in `string_b`.
2. The method sets `transpositions` to 0.
3. The method reads each character of `string_a`, from the first to the last.
4. If the character at position `i` has no match, the method ignores the character.
5. If the character has a match, the method moves `k` forward. The value `k` stops at the next position in `string_b` that has a match.
6. The method compares two characters: the character from `string_a`, and the character at position `k` in `string_b`.
7. If the two characters are different, the method adds 1 to `transpositions`.
8. The method moves `k` forward one position, and continues with the next character of `string_a`.
9. At the end, the method divides `transpositions` by 2. Ruby divides integers, thus the result has no decimal part.
10. The method gives this value.

## Why the method divides by two

The method examines the two lists of characters that have matches, in the same sequence. If two characters are in the wrong sequence, the comparison finds a difference two times — one time at each position. Thus the method divides the count by 2.

Example: `"an"` and `"na"`. All characters have matches. The comparison finds `a` against `n`, then `n` against `a`. The count is 2. The method gives 1.

## The loop on line 114

The command `k += 1 until matches_b[k]` has no test for the end of the array. The loop is safe, because the two arrays contain an equal quantity of `true` values. `count_matches` makes one `true` value in `matches_b` for each `true` value in `matches_a`. Thus a `true` value is always available.

## The effect on the result

`jaro_similarity` uses the value in the expression `(matches - transpositions) / matches` (line 88). More transpositions make the score lower. `jaro_winkler` then increases the score if the two names have equal first letters (maximum four letters, line 122). A score of 0.85 or more puts the author in the `:review` status (line 25).
