# The method `count_transpositions`

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

## 1. Function of the method

The method counts the transpositions between two strings.

A transposition is a pair of characters that are in the two strings, but in a
different sequence. The method `jaro_similarity` uses this count to decrease
the similarity value of two names.

The method does not find the characters that agree. The method `count_matches`
finds them before. This method only compares the sequence of these characters.

## 2. The data that the method receives

The method receives four items:

- `string_a` is the first string.
- `string_b` is the second string.
- `matches_a` is a list of true and false values. The list has one value for
  each character of `string_a`. The value is true if the character has an
  agreement in `string_b`.
- `matches_b` is the same type of list for the characters of `string_b`.

The two lists always contain the same number of true values, because
`count_matches` sets one value in each list for each agreement.

## 3. The two positions

The method uses two positions:

- The position `i` moves through `string_a`. It moves one character at a time,
  from the first character to the last character.
- The position `k` moves through `string_b`. It starts at 0. It stops only at
  the characters that have an agreement.

The position `k` never moves to the rear. Thus the method reads the two groups
of agreed characters in the same direction.

## 4. The steps of the method

1. Set `k` to 0. Set `transpositions` to 0.
2. Read the character at the position `i` of `string_a`.
3. If `matches_a[i]` is false, do not do the subsequent steps. Continue with the
   next character of `string_a`.
4. If `matches_a[i]` is true, move `k` forward until `matches_b[k]` is true.
   This gives the next agreed character of `string_b`.
5. Compare the character from `string_a` with the character at the position `k`
   of `string_b`.
6. If the two characters are different, add 1 to `transpositions`.
7. Move `k` forward one position.
8. Do steps 2 to 7 again for each subsequent character of `string_a`.
9. Divide `transpositions` by 2. This number is the result.

Step 4 is safe, because the two lists contain the same number of true values.
For each agreed character of `string_a`, there is one agreed character of
`string_b`. Thus `k` always finds a true value before the end of the list.

## 5. Example

These two names have an agreement for all six characters:

```
string_a = "martha"
string_b = "marhta"
```

| `i` | Character in `string_a` | `k` | Character in `string_b` | Result       |
|-----|-------------------------|-----|-------------------------|--------------|
| 0   | m                       | 0   | m                       | the same     |
| 1   | a                       | 1   | a                       | the same     |
| 2   | r                       | 2   | r                       | the same     |
| 3   | t                       | 3   | h                       | different    |
| 4   | h                       | 4   | t                       | different    |
| 5   | a                       | 5   | a                       | the same     |

The method finds two differences. It divides 2 by 2. The result is 1
transposition. The letters `t` and `h` are the transposed pair.

## 6. Why the method divides by 2

The method compares two groups of characters. The two groups contain the same
characters, but the sequence can be different.

When two characters change their positions, the method finds two differences.
It finds one difference at the position of the first character. It finds a
second difference at the position of the second character. Thus the method
counts each transposition two times. The division by 2 gives the correct
number.

The division is an integer division. If the number of differences is an odd
number, Ruby removes the fraction. For example, the strings `"acba"` and
`"aacbad"` give three differences, and the result is 1. This behavior agrees
with the standard Jaro algorithm.

## 7. How the result is used

The method `jaro_similarity` uses the result in this calculation:

```
((matches / length_of_string_a) +
 (matches / length_of_string_b) +
 ((matches - transpositions) / matches)) / 3.0
```

The third part of the calculation contains the transpositions. If the number of
transpositions increases, the value of this part decreases. Thus two names with
the same characters in a different sequence get a lower similarity value than
two names with the same characters in the same sequence.

For `"martha"` and `"marhta"`, the six agreements and the one transposition
give the value 0.9444. The method `jaro_winkler` then adds a bonus for the
three equal characters at the start (`mar`). The final value is 0.9611. This
value is more than the threshold 0.85. Thus the service `Authors::MatchByName`
gives the status `:review` for these two names.
