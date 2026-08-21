# `count_transpositions` in `Authors::MatchByName`

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

## What it computes

This is the `t` term of the Jaro similarity formula. Jaro asks two questions about two
strings: how many characters do they have in common, and are those common characters in
the same order? `count_matches` answers the first question. `count_transpositions`
answers the second one: among the characters that already matched, how many pairs are out
of order.

`jaro_similarity` uses the return value in the third term of the average:

```ruby
((matches.to_f / string_a.length) +
  (matches.to_f / string_b.length) +
  ((matches - transpositions).to_f / matches)) / 3.0
```

So the return value is a penalty. Zero transpositions means the shared characters appear
in the same relative order in both strings, and the third term is `1.0`.

## The inputs

The method never decides what matches. It runs after `count_matches` and reuses that
work:

- `matches_a` — one boolean per character of `string_a`. `true` means that character found
  a partner in `string_b` inside the match window.
- `matches_b` — the same for `string_b`, marking which characters were consumed as
  partners.

Two properties from `count_matches` are what make this method work:

1. Both arrays hold exactly the same number of `true` entries, because each match sets one
   flag in each array.
2. The flags describe a pairing, but the pairing itself is not stored. Only the positions
   survive.

## How it works, line by line

The method rebuilds a pairing by position instead of by identity. It reads the matched
characters of `string_a` from left to right and the matched characters of `string_b` from
left to right, and lines up the first with the first, the second with the second, and so
on.

- `k` is the read cursor into `string_b`. It only moves forward, never resets.
- `string_a.each_char.with_index` walks `string_a`, and `next unless matches_a[i]` skips
  every character that never matched. Unmatched characters are not this method's concern —
  they were already penalised by the first two terms of the Jaro formula.
- `k += 1 until matches_b[k]` advances the cursor to the next matched character in
  `string_b`, stepping over unmatched ones.
- `transpositions += 1 if char != string_b[k]` compares the two matched characters now
  facing each other. If they differ, the shared characters are in a different order in the
  two strings, and this position counts as a half transposition.
- `k += 1` consumes that position of `string_b` so the next iteration pairs with the
  following matched character.

The loop cannot run off the end of `string_b`. The number of iterations that reach the
cursor code equals the number of `true` entries in `matches_a`, which equals the number in
`matches_b`, so a matched position is always still available.

## Why divide by two

The count accumulated in the loop is the number of *positions* that disagree, not the
number of swaps. A single swap of two adjacent matched characters makes both of those
positions disagree, so it is counted twice. Halving converts mismatched positions back
into swaps. This matches the classic Jaro definition, where `t` is half the number of
matched characters that are in a different sequence order.

The division is Ruby integer division, so it floors. That matters only in unusual cases
such as a cyclic rotation, where three positions disagree because of what is really more
than one swap; the standard formula floors there as well.

## Worked example: `"martha"` vs `"marhta"`

The match distance is `(6 / 2) - 1 = 2`, and all six characters match, so `matches_a` and
`matches_b` are all `true`.

| step | `char` from a | `k` | `string_b[k]` | differ? |
|------|---------------|-----|---------------|---------|
| 0    | `m`           | 0   | `m`           | no      |
| 1    | `a`           | 1   | `a`           | no      |
| 2    | `r`           | 2   | `r`           | no      |
| 3    | `t`           | 3   | `h`           | yes     |
| 4    | `h`           | 4   | `t`           | yes     |
| 5    | `a`           | 5   | `a`           | no      |

Two disagreeing positions, so the method returns `2 / 2 = 1`. Jaro similarity comes out at
`0.9444`, the textbook value for this pair.

## Worked example with skipping: `"jones"` vs `"johnson"`

Here the cursor jump matters. `count_matches` marks `j`, `o`, `n`, `s` in `"jones"`
(the `e` finds no partner) and positions 0, 1, 3, 4 in `"johnson"` — the `h` at index 2
and the trailing `o` and `n` stay unmatched.

The loop skips index 3 of `string_a` because `matches_a[3]` is `false`. When it reaches
`n`, the cursor sits at index 2 of `string_b`, which is unmatched, so `k += 1 until
matches_b[k]` moves it to index 3. The pairs are `j`/`j`, `o`/`o`, `n`/`n`, `s`/`s`, all
equal, and the method returns `0`. The unmatched characters lower the score through the
`matches / length` terms instead.

## Where it sits in the class

`count_transpositions` is a private helper three levels down: `call` →
`find_best_fuzzy_match` → `jaro_winkler` → `jaro_similarity` → `count_transpositions`. It
runs on the downcased strings, because `jaro_winkler` downcases before calling
`jaro_similarity`. It is called once per candidate author per name field, inside a
`find_each` loop over every author, so it runs on short strings but many times.
