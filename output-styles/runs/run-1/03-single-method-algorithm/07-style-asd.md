The `rails_*` MCP tools are not connected, so I used `Read`.

## `count_transpositions` — lines 108–119

This private method is one step of the Jaro similarity algorithm. `jaro_similarity` calls it at line 84, after `count_matches` finds the matched characters.

### Input

The method receives four values:

| Value | Content |
|---|---|
| `string_a`, `string_b` | The two strings, in lower case |
| `matches_a` | An array of booleans. `matches_a[i]` is `true` if character `i` of `string_a` has a match |
| `matches_b` | The same array for `string_b` |

`count_matches` fills the two boolean arrays. It sets one flag in each array for each match. Thus the two arrays hold the same number of `true` values.

### Operation

The method compares the matched characters of the two strings in sequence. It counts the positions where the two sequences disagree.

1. `k = 0` — this variable is a pointer into `matches_b`.
2. The loop reads each character of `string_a` with its index `i` (line 111).
3. `next unless matches_a[i]` — the method ignores each character that has no match (line 112).
4. `k += 1 until matches_b[k]` — the pointer `k` moves forward to the next matched position in `string_b` (line 114).
5. `transpositions += 1 if char != string_b[k]` — if the two matched characters are different, the counter increases (line 115).
6. `k += 1` — the pointer moves past this position, for the next cycle of the loop (line 116).
7. `transpositions / 2` — the method divides the count by two and returns the result (line 118).

### Why the division by two

A transposition is a swap of two characters. A swap makes two positions disagree, not one. The division by two thus changes the count of unequal positions into a count of swaps. Ruby integer division also removes the remainder, as the Jaro definition requires.

### Example

For `"martha"` and `"marhta"`, all six characters match. The two matched sequences are:

```
a: m a r t h a
b: m a r h t a
```

Positions 3 and 4 disagree. The count is 2. The method returns 1.

### Two points to know

- **The `until` loop has no bound test.** If `k` goes past the end of `matches_b`, `matches_b[k]` returns `nil` and the loop does not stop. The code is safe only because `count_matches` puts an equal number of `true` values in the two arrays. The loop therefore always finds another `true` flag.
- **The result feeds the third term of the Jaro formula** at line 88: `(matches - transpositions).to_f / matches`. More transpositions give a lower similarity score. `jaro_winkler` then adds the prefix bonus (line 68), and `call` compares the score against `REVIEW_THRESHOLD` (0.85).
