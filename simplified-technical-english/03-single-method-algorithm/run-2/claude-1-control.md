# How `count_transpositions` works

```ruby
def count_transpositions(string_a, string_b, matches_a, matches_b)
  k = 0
  transpositions = 0
  string_a.each_char.with_index do |char, i|
    next unless matches_a[i]

    k += 1 until matches_b[k]
    transpositions += 1 if char != string_b[k]
    k += 1
  end
  transpositions / 2
end
```

This method is the third term of the Jaro similarity formula used by `Authors::MatchByName` to fuzzy match author names. It answers one question: of the characters the two strings have in common, how many pairs appear in a different order?

## The state it inherits

`count_transpositions` never runs on its own. It runs after `count_matches`, and it depends entirely on the two boolean arrays that `count_matches` filled in:

- `matches_a[i]` is `true` when the character at position `i` in `string_a` found a partner in `string_b` inside the sliding window of `match_distance` characters.
- `matches_b[j]` is `true` when the character at position `j` in `string_b` was claimed as that partner.

`count_matches` pairs characters greedily and marks each position in `string_b` as taken (`next if matches_b[j]`), so the two arrays contain exactly the same number of `true` values. That guarantee is what makes the walk below safe.

Concretely, the flagged positions describe two subsequences: the matched characters of `string_a`, and the matched characters of `string_b`. Those two subsequences contain the same characters. Only their order can differ.

## The walk itself

The method compares those two subsequences position by position, using two independent cursors.

`i` walks `string_a` from left to right through `each_char.with_index`. The guard `next unless matches_a[i]` skips every character that never found a partner, so `i` only stops on matched positions.

`k` is a manual cursor into `string_b`. It is declared once before the loop, so it keeps its value across iterations and never rewinds. The line `k += 1 until matches_b[k]` pushes `k` forward until it lands on the next matched position in `string_b`, skipping over unmatched characters exactly the way the `next` guard skips them in `string_a`.

At that point both cursors sit on the n-th matched character of their respective strings. The comparison `char != string_b[k]` asks whether those two aligned characters are the same. If they differ, the algorithm has found one position where the shared characters appear out of order, and `transpositions` goes up by one. Finally `k += 1` moves past the position just consumed so the next iteration starts its scan after it.

## Why the result is divided by two

Every out of order pair produces two mismatched positions, one at each end of the swap. Take `martha` and `marhta`. Both strings match on all six characters, so the walk aligns `m a r t h a` against `m a r h t a`. Positions 0, 1, 2 and 5 agree. Position 3 compares `t` against `h` and position 4 compares `h` against `t`. The raw counter reaches 2, and a single swap of adjacent characters is what actually happened. Dividing by two turns "mismatched positions" into "transposed pairs", which is the value the Jaro formula expects.

The division is Ruby integer division, so it floors. That matters only in the rarer case where the shared characters form a cycle of odd length, for example matched subsequences `abc` and `bca`, which produce 3 mismatched positions and report 1. Flooring here is the conventional behaviour of Jaro implementations, not a bug.

## Where the number goes

Back in `jaro_similarity`, the count feeds the last of three averaged terms:

```ruby
((matches.to_f / string_a.length) +
  (matches.to_f / string_b.length) +
  ((matches - transpositions).to_f / matches)) / 3.0
```

The first two terms reward coverage, meaning how much of each string participated in a match. The third term, `(matches - transpositions) / matches`, rewards agreement in ordering. When the shared characters line up perfectly the term is `1.0` and contributes nothing negative. Each transposed pair shaves one unit off the numerator, so scrambled names score lower than identical ones even when they contain the same letters.

`jaro_winkler` then adds its prefix bonus on top, and `find_best_fuzzy_match` keeps the highest scoring author. Only scores at or above `REVIEW_THRESHOLD` (0.85) come back as a `:review` result.

## Two details worth noticing

The loop `k += 1 until matches_b[k]` has no upper bound check. If it ever ran past the end of `matches_b`, `matches_b[k]` would return `nil`, the condition would stay falsey, and the loop would spin forever. It cannot happen here because `matches_a` and `matches_b` hold an equal number of `true` values, so the n-th advance always finds an n-th match. The safety lives in the invariant established by `count_matches`, not in this method.

The method is also insensitive to unmatched characters. They are skipped on both sides, which is correct: characters that appear in only one of the two strings are already penalised by the coverage terms of the formula, and counting them here would penalise them twice.
