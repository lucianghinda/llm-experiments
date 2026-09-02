`count_transpositions` (app/services/authors/match_by_name.rb:108) is the second half of the Jaro similarity formula. It runs *after* `count_matches`, which has already filled the two boolean masks `matches_a` / `matches_b` marking which characters in each string found a partner within the sliding window.

How it works:

1. `k` is a cursor into `string_b` that only ever moves forward, tracking "the next matched character in b I haven't consumed yet."
2. It iterates `string_a` by index, skipping any position that wasn't matched (`next unless matches_a[i]`).
3. For each matched char in a, `k += 1 until matches_b[k]` advances `k` to the next matched position in b. This pairs the *n*-th matched char of a with the *n*-th matched char of b — order of appearance, not position.
4. If that pair disagrees (`char != string_b[k]`), the matched characters appear in a different relative order in the two strings, so it counts one. Then `k += 1` consumes that slot.
5. `transpositions / 2` — every out-of-order swap produces two disagreeing pairs (one at each end), so the raw count is halved.

Worked example, `"martha"` vs `"marhta"`: all six chars match. Walking in order gives pairs m/m, a/a, r/r, t/h, h/t, a/a — two disagreements → 1 transposition. Feeding that into line 86: `(6/6 + 6/6 + 5/6) / 3 ≈ 0.944`.

One fragility worth knowing: `k += 1 until matches_b[k]` has no bounds check. Past the end of the array `matches_b[k]` returns `nil`, which is falsy, so it would spin forever. It's safe today only because `count_matches` sets `matches_a[i]` and `matches_b[j]` in the same breath (lines 99-100), guaranteeing both masks hold an equal number of `true`s — so the cursor can never outrun them. If that invariant ever breaks, this loop hangs rather than raising.
