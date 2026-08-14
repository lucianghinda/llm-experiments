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

## What it is for

This method is one step inside the Jaro similarity calculation in `Authors::MatchByName`. Jaro scores two strings using three quantities: how many characters of `string_a` are matched, how many characters of `string_b` are matched, and how many of those matched characters sit in a different order in the two strings. `count_transpositions` computes that third quantity.

The Jaro formula that consumes it lives in `jaro_similarity`:

```ruby
((matches.to_f / string_a.length) +
  (matches.to_f / string_b.length) +
  ((matches - transpositions).to_f / matches)) / 3.0
```

So a higher transposition count pulls the score down, because fewer matched characters count as being in agreement.

## The inputs

The method never decides which characters match. That work already happened in `count_matches`, which ran first and filled in two boolean arrays:

- `matches_a[i]` is `true` when character `i` of `string_a` found a partner in `string_b` inside the allowed match window.
- `matches_b[j]` is `true` when character `j` of `string_b` was claimed as that partner.

`count_matches` sets a pair of flags only when the two characters are equal, and it marks each position at most once. That gives two facts this method depends on: the number of `true` entries in `matches_a` equals the number of `true` entries in `matches_b`, and the matched characters of `string_a` are the same multiset of characters as the matched characters of `string_b`. Only the order can differ.

## The walk

The method compares the two sequences of matched characters position by position, ignoring every unmatched character.

`i` walks through `string_a` via `each_char.with_index`. `k` is a separate cursor into `string_b` that is never reset, so it only ever moves forward across the whole run.

For each index `i`:

1. `next unless matches_a[i]` skips characters of `string_a` that were never matched. They contribute nothing here.
2. `k += 1 until matches_b[k]` advances the `string_b` cursor to the next matched position. If `k` already points at a matched position the loop body never runs and `k` stays where it is.
3. `transpositions += 1 if char != string_b[k]` compares the nth matched character of `string_a` against the nth matched character of `string_b`. They are guaranteed to both be matched characters, but not guaranteed to be the same character. When they differ, the two strings placed their matched characters in a different order at this position.
4. `k += 1` steps past the position just consumed, so the next iteration looks for a fresh matched position in `string_b`.

Because `k` moves forward only, the first matched character of `string_a` is paired with the first matched character of `string_b`, the second with the second, and so on. The result is a straight zip of the two filtered sequences.

## Why the result is divided by two

The loop counts positions where the two filtered sequences disagree, not swaps. A single swap of two characters shows up as two disagreeing positions, one at each end of the swap, so the raw count is roughly double the number of swaps. Dividing by two converts the count of misplaced positions into the count of transpositions that Jaro expects.

## A worked example

Take `"martha"` and `"marhta"`, the classic Jaro example. Every character matches, so `matches_a` and `matches_b` are all `true` and the walk compares all six positions:

| position | `string_a` | `string_b` | disagree? |
| --- | --- | --- | --- |
| 0 | m | m | no |
| 1 | a | a | no |
| 2 | r | r | no |
| 3 | t | h | yes |
| 4 | h | t | yes |
| 5 | a | a | no |

The raw count is 2, and `2 / 2` returns 1. One transposition, which is the expected answer for a single swapped pair. Feeding that into the formula gives `(6/6 + 6/6 + 5/6) / 3`, or about `0.944`.

Now take `"jon"` and `"jno"`. All three characters match, positions 1 and 2 disagree, the raw count is 2, and the method returns 1 again. Same shape, same answer.

## Details worth knowing

**The unmatched characters are already accounted for.** They lower the score through the `matches / length` terms of the Jaro formula, not through this method. That is why the loop skips them instead of penalising them.

**`transpositions / 2` is Ruby integer division, so it floors.** For a swap of two characters the raw count is even and the division is exact. For a rotation such as `"abc"` against `"bca"` all three positions disagree, and the reference Jaro definition uses `3 / 2 = 1.5` while this code produces `1`. That makes the score slightly more generous than the textbook formula in the rare cases where the disagreement count is odd. Most published implementations do the same thing, so it is a known simplification rather than an accident, but it is a real difference if you ever compare these scores against another library.

**The `until` loop has no bound check.** `k += 1 until matches_b[k]` reads past the end of the array as `nil`, which is falsy, so it would spin forever if it ran out of matched positions in `string_b`. That cannot happen here because `count_matches` guarantees `matches_b` holds exactly as many `true` entries as `matches_a`, and the loop consumes one per matched character of `string_a`. The safety of this method rests entirely on that invariant holding in `count_matches`.

**Cost.** The `k` cursor never rewinds, so across the whole call it advances at most `string_b.length` times. Combined with the single pass over `string_a`, the method is linear in the length of the two strings.
