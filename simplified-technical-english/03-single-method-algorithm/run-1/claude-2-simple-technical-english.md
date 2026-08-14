# How `count_transpositions` works

## Purpose

The method counts how many matched characters are in the wrong order.

It is one step of the Jaro similarity calculation. Jaro similarity gives a score
between 0.0 and 1.0 for two strings. The score goes down when characters are
matched but out of order.

## Where the method is used

The file is
`app/services/authors/match_by_name.rb`.

The method `jaro_similarity` calls two private methods in this order:

1. `count_matches` finds the characters that appear in both strings.
2. `count_transpositions` counts how many of those characters are out of order.

`jaro_similarity` then uses both numbers in the final formula.

## The inputs

The method takes four arguments.

| Argument | Type | Content |
|---|---|---|
| `string_a` | String | The first string, in lower case |
| `string_b` | String | The second string, in lower case |
| `matches_a` | Array of booleans | One flag for each character of `string_a` |
| `matches_b` | Array of booleans | One flag for each character of `string_b` |

`count_matches` fills the two arrays before this method runs. A flag is `true`
when `count_matches` paired that character with a character in the other string.
A flag is `false` when the character has no pair.

Two facts are important:

- The two arrays hold the same number of `true` flags. Every match sets one flag
  in each array.
- The arrays record the positions of the matched characters. They do not record
  which character is paired with which character.

## The code

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

## Step by step

The method reads the matched characters of both strings from left to right. It
compares them in pairs.

1. `k = 0` sets the read position in `string_b`. This variable keeps its value
   between loop steps.
2. `transpositions = 0` sets the counter to zero.
3. The loop reads each character of `string_a`. The variable `char` holds the
   character. The variable `i` holds its index.
4. `next unless matches_a[i]` skips the character if it has no match. Unmatched
   characters are not part of the comparison.
5. `k += 1 until matches_b[k]` moves `k` forward until it points at the next
   matched character of `string_b`. Unmatched characters of `string_b` are
   skipped in the same way.
6. `transpositions += 1 if char != string_b[k]` compares the two matched
   characters. The counter goes up by one when the characters are different.
7. `k += 1` moves past the character that was just used. The next loop step
   starts the search after this position.
8. `transpositions / 2` returns half of the counter. The division is integer
   division, because both operands are integers.

## Why the method divides by two

One pair of characters in the wrong order produces two differences, not one.

Look at `string_a = "ab"` and `string_b = "ba"`. Both characters match, so all
four flags are `true`. The loop makes two comparisons:

- Position 0: `"a"` against `"b"`. The characters are different. The counter
  becomes 1.
- Position 1: `"b"` against `"a"`. The characters are different. The counter
  becomes 2.

There is only one swap, but the loop counts it twice. The division by two
corrects the number.

## Worked example

Take `string_a = "martha"` and `string_b = "marhta"`.

`count_matches` pairs all six characters, so every flag is `true`. No character
is skipped.

| `i` | Character of `string_a` | `k` | Character of `string_b` | Equal? | Counter |
|---|---|---|---|---|---|
| 0 | `m` | 0 | `m` | yes | 0 |
| 1 | `a` | 1 | `a` | yes | 0 |
| 2 | `r` | 2 | `r` | yes | 0 |
| 3 | `t` | 3 | `h` | no | 1 |
| 4 | `h` | 4 | `t` | no | 2 |
| 5 | `a` | 5 | `a` | yes | 2 |

The counter is 2. The method returns `2 / 2`, which is 1. The strings have one
transposition, because `t` and `h` are swapped.

## How the result is used

`jaro_similarity` puts the result into the third term of its formula:

```ruby
((matches.to_f / string_a.length) +
  (matches.to_f / string_b.length) +
  ((matches - transpositions).to_f / matches)) / 3.0
```

The third term is the fraction of matched characters that are in the correct
order. More transpositions make this fraction smaller, so the similarity score
goes down.

## Conditions the method depends on

The method is safe only because the caller guarantees three conditions.

1. `count_matches` ran first and filled both arrays.
2. `matches_b` holds at least as many `true` flags as `matches_a`. This is always
   true, because each match sets one flag in each array. Without this condition,
   the line `k += 1 until matches_b[k]` never stops. In Ruby, an index outside an
   array returns `nil`, and `nil` is false, so the loop keeps counting up.
3. The number of matches is more than zero. `jaro_similarity` returns 0.0 before
   this point when there are no matches.

The method also assumes that both strings are already in lower case. The method
`jaro_winkler` calls `downcase` on both strings before it calls
`jaro_similarity`, so the comparison is not case sensitive.
