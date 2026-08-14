# The method count_transpositions

## Function of the method

The method counts the transpositions between two strings.

A transposition is one pair of characters. The two characters are in both
strings. But they are in a different sequence in each string.

The method is one part of the Jaro similarity calculation. The Jaro
calculation gives a score between 0.0 and 1.0. The score becomes lower when
the strings contain more transpositions.

## Location of the method

The method is in this file:

`app/services/authors/match_by_name.rb`

The method `jaro_similarity` calls two private methods. It calls them in this
sequence:

1. The method `count_matches` finds the characters that are in the two
   strings.
2. The method `count_transpositions` counts the pairs of characters that are
   in the wrong sequence.

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

## The four parameters

The method has four parameters:

| Parameter | Type | Content |
|---|---|---|
| `string_a` | String | The first string, in lower case |
| `string_b` | String | The second string, in lower case |
| `matches_a` | Array | One value for each character of `string_a` |
| `matches_b` | Array | One value for each character of `string_b` |

Each value in the two arrays is `true` or `false`. The value is `true` when
the character at that position has a pair in the other string. The value is
`false` when the character has no pair.

The method `count_matches` puts these values in the two arrays. It does this
before `count_transpositions` starts.

The two arrays contain the same number of `true` values. Each pair of
characters sets one value in `matches_a` and one value in `matches_b`.

The arrays do not show which character is the pair of which character. The
arrays show only the positions.

## The two counters

The method uses two counters:

- The counter `k` holds a position in `string_b`. Its initial value is 0. The
  method keeps this value for all the characters of `string_a`.
- The counter `transpositions` holds the number of characters that do not
  agree. Its initial value is 0.

## The procedure

The method examines each character of `string_a`. It starts at the left and
moves to the right. The variable `char` holds the character. The variable `i`
holds the position of the character.

For each character, the method does these steps:

1. Read the value in `matches_a` at position `i`.
2. If the value is `false`, do not do steps 3 to 6. Go to the next character
   of `string_a`.
3. Increase `k` by 1 again and again. Stop when the value in `matches_b` at
   position `k` is `true`. The counter `k` now shows the next character of
   `string_b` that has a pair.
4. Compare `char` with the character of `string_b` at position `k`.
5. If the two characters are different, increase `transpositions` by 1.
6. Increase `k` by 1. This step prevents a second use of the same position in
   `string_b`.

After the last character of `string_a`, the method divides `transpositions` by
2. The method gives this result to `jaro_similarity`.

## The division by 2

One pair of characters in the wrong sequence gives two differences. The
division by 2 changes the number of differences into the number of
transpositions.

Look at this example. `string_a` is `"ab"`. `string_b` is `"ba"`. All four
values in the two arrays are `true`. The method makes two comparisons:

- At position 0, the method compares `"a"` with `"b"`. The two characters are
  different. The counter becomes 1.
- At position 1, the method compares `"b"` with `"a"`. The two characters are
  different. The counter becomes 2.

The two strings have only one transposition. But the counter is 2. The
division by 2 gives the correct number.

The two operands are integers. Ruby thus does an integer division. The result
has no fraction part.

## An example with more characters

`string_a` is `"martha"`. `string_b` is `"marhta"`.

The method `count_matches` makes a pair for all six characters. All the values
in the two arrays are `true`. The method does not ignore a character.

| `i` | Character of `string_a` | `k` | Character of `string_b` | Equal | Counter |
|---|---|---|---|---|---|
| 0 | `m` | 0 | `m` | yes | 0 |
| 1 | `a` | 1 | `a` | yes | 0 |
| 2 | `r` | 2 | `r` | yes | 0 |
| 3 | `t` | 3 | `h` | no | 1 |
| 4 | `h` | 4 | `t` | no | 2 |
| 5 | `a` | 5 | `a` | yes | 2 |

The final value of the counter is 2. The method divides 2 by 2. The result is
1. The two strings have one transposition. The characters `t` and `h` are in a
different sequence.

## Use of the result

The method `jaro_similarity` puts the result in the third term of its formula:

```ruby
((matches.to_f / string_a.length) +
  (matches.to_f / string_b.length) +
  ((matches - transpositions).to_f / matches)) / 3.0
```

The third term gives the part of the pairs that are in the correct sequence. A
larger number of transpositions makes this term smaller. A smaller term makes
the similarity score lower.

## Necessary conditions

The method is correct only if the caller obeys three conditions.

1. The method `count_matches` operates first. It fills the two arrays.
2. The array `matches_b` contains a minimum of the same number of `true`
   values as the array `matches_a`.
3. The number of pairs is more than 0.

Caution: if condition 2 is not correct, step 3 of the procedure does not stop.
Ruby gives the value `nil` for an index that is not in an array. The value
`nil` is not `true`. The counter `k` thus increases without a limit. The
method `count_matches` always makes condition 2 correct.

The method `jaro_similarity` gives the value 0.0 before this point if the
number of pairs is 0. Condition 3 is thus always correct.

The two strings must be in lower case. The method `jaro_winkler` calls
`downcase` on the two strings. It does this before it calls `jaro_similarity`.
The comparison is thus not sensitive to the case of the characters.
