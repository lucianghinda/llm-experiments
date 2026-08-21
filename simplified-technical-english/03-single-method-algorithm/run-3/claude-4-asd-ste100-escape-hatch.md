# How `count_transpositions` works

`Authors::MatchByName#count_transpositions` is one step of the Jaro similarity
calculation. The app uses that similarity to compare an author name with the
names in the database.

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

## What the method receives

The method receives four values:

- `string_a` and `string_b` are the two names in lower case.
- `matches_a` is an array of true and false values. It has one entry for each
  character of `string_a`. The entry is true if the character has a partner in
  `string_b`.
- `matches_b` is the same kind of array for `string_b`.

The method `count_matches` makes these two arrays. That method pairs each
character of `string_a` with a character of `string_b` that is equal and near.
It marks both positions as true. Therefore the two arrays contain the same
number of true entries.

## The idea

The match step tells you *which* characters the two names have in common. It
does not tell you if these characters are in the same order. This method
measures the difference in order.

Take the matched characters of `string_a` in their order. This is the first
list. Take the matched characters of `string_b` in their order. This is the
second list. Both lists have the same length. The method compares the two lists
position by position. Each position where the two characters disagree is one
half of a swap.

## The loop, step by step

The method keeps two counters:

- `i` is the position in `string_a`. The `each_char.with_index` loop moves it.
- `k` is the position in `string_b`. The code moves it only forward.

For each character of `string_a`:

1. `next unless matches_a[i]` skips the character if it has no partner. Only
   matched characters are part of the comparison.
2. `k += 1 until matches_b[k]` moves `k` forward to the next matched position
   in `string_b`. The loop stops immediately if `k` is already at a matched
   position.
3. `transpositions += 1 if char != string_b[k]` compares the two characters at
   the same rank in the two lists. The counter increases if they are different.
4. `k += 1` moves past the position that the code just used. The next cycle
   starts the search after this position.

Because `k` never moves back, the method reads each string one time. The cost
grows in a linear manner with the length of the names.

## Why the result is divided by two

One swap of two neighbour characters makes two positions disagree. Position one
holds the wrong character, and position two holds the other wrong character.
The counter thus increases two times for one swap. The division `/ 2` removes
this factor.

`/` is an integer division in Ruby. It removes the fraction. If the number of
disagreements is odd, the result rounds down. This behaviour agrees with the
usual definition of the Jaro metric.

## An example

Compare `"martha"` with `"marhta"`.

The match step pairs all six characters. The matched list from `"martha"` is
`m a r t h a`. The matched list from `"marhta"` is `m a r h t a`.

| Rank | From `martha` | From `marhta` | Agree? |
|------|---------------|---------------|--------|
| 1    | m             | m             | yes    |
| 2    | a             | a             | yes    |
| 3    | r             | r             | yes    |
| 4    | t             | h             | no     |
| 5    | h             | t             | no     |
| 6    | a             | a             | yes    |

Two positions disagree. The method returns `2 / 2 = 1`. The two names have one
transposition, which is correct: `th` became `ht`.

## How the caller uses the result

`jaro_similarity` puts the value in the third part of the formula:

```ruby
((matches.to_f / string_a.length) +
  (matches.to_f / string_b.length) +
  ((matches - transpositions).to_f / matches)) / 3.0
```

The first two parts measure how much of each name is matched. The third part
measures the order. A larger number of transpositions makes the third part
smaller. Thus the score decreases.

For `"martha"` and `"marhta"` the score is `(1 + 1 + 5/6) / 3`, which is
approximately `0.944`.

## Two conditions that the method depends on

- `jaro_similarity` calls the method only when `matches` is more than zero.
  Thus the division `transpositions / 2` is safe, and the loop has work to do.
- The loop `k += 1 until matches_b[k]` has no upper limit test. If `matches_b`
  contained fewer true entries than `matches_a`, then `matches_b[k]` would give
  `nil` after the end of the array. `nil` is false, and the loop would not stop.
  `count_matches` marks one position in each array for each pair. Therefore the
  counts are always equal, and the loop always finds a true entry. The safety of
  this method depends on that guarantee from `count_matches`.
