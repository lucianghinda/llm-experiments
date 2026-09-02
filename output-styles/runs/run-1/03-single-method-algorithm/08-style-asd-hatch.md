`count_transpositions` is at app/services/authors/match_by_name.rb:108. It is the second half of the Jaro similarity calculation (`jaro_similarity`, line 71), which `jaro_winkler` uses to score author names.

## What it receives

`count_matches` (line 91) runs first. It walks `string_a` and, for each character, looks in `string_b` inside a window of `± distance` positions for the same character that is not yet claimed. When it finds one, it sets two flags:

- `matches_a[i] = true` — character `i` of `string_a` has a partner.
- `matches_b[j] = true` — character `j` of `string_b` is that partner.

So the two boolean arrays hold the same number of `true` values, but the flags do not record *which* character pairs with which. They record only *that* a character has a partner.

## What the method does

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

The method rebuilds the pairing by order, not by the window search:

1. It goes through `string_a` and ignores every character that has no match (line 112).
2. `k` is a cursor into `string_b`. Line 114 moves `k` forward until it points at the next flagged character in `string_b`. This gives the matched characters of `string_b` in sequence.
3. Line 115 compares the two matched characters that are at the same rank. If they are different, the pair is out of order, so the counter increases.
4. Line 116 moves the cursor past the character it just used, so the next iteration takes the following match.

The result is: take the matched characters of `string_a` in order, take the matched characters of `string_b` in order, and count the positions where the two sequences disagree.

5. Line 118 divides by 2. Characters that are out of order always disagree in pairs — if `a` has `x` where `b` has `y`, some later position has `y` where `b` has `x`. One swap therefore causes two disagreements, and the division converts disagreements into swaps.

## Example

`martha` against `marhta`. All six characters match, so both flag arrays are all `true`. The two matched sequences are `m a r t h a` and `m a r h t a`. They disagree at rank 4 (`t` vs `h`) and rank 5 (`h` vs `t`): `transpositions` = 2, and the method returns 1.

`jaro_similarity` (line 86) then computes `(6/6 + 6/6 + (6-1)/6) / 3 = 0.944`. `jaro_winkler` adds the prefix bonus for the shared `mar`: `0.944 + 3 × 0.1 × (1 - 0.944) ≈ 0.961`.

## Two notes on the code

**The unguarded `k += 1 until matches_b[k]` is safe, but only by an invariant.** `matches_b[k]` returns `nil` for an index past the end of the array, and `nil` is falsy, so the loop would never stop. It cannot happen here because `count_matches` always sets one flag in `matches_a` and one in `matches_b` together, so the two arrays hold an equal count of `true`. The cursor therefore always finds a flagged position before it runs out. The correctness of this method depends on that property of a different method — worth a comment if anyone changes `count_matches`.

**`transpositions / 2` is integer division.** The disagreement count is even for a simple swap, but not for a longer rotation: `abc` against `bca` gives three disagreements, and the method returns 1 instead of 1.5. This makes the score a little higher than the strict Jaro definition. The effect is small and it only applies to rotated names, so it is unlikely to move a score across the `REVIEW_THRESHOLD` of 0.85 — but it is a deviation from the reference algorithm.
