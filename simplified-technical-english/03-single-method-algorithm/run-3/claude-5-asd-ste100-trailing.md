# The method `count_transpositions`

## Location

The method is in `app/services/authors/match_by_name.rb`, lines 108 to 119. It is a private method of the class `Authors::MatchByName`.

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

## Function

The method counts the transpositions between two strings. A transposition is a pair of characters that occurs in the two strings in a different sequence. The Jaro similarity formula needs this count. The class uses the Jaro-Winkler score to find the author whose name is the most similar to a given name.

## Inputs

The method has four parameters:

- `string_a` and `string_b` are the two names in lower case.
- `matches_a` is an array with one item for each character of `string_a`. The item is `true` if the character has a partner character in `string_b`.
- `matches_b` is the equivalent array for the characters of `string_b`.

The method `count_matches` fills the two arrays before `count_transpositions` starts. For each pair of characters that it finds, `count_matches` sets one item to `true` in each array. Thus the two arrays hold the same number of `true` items.

## The procedure

1. The method sets `k` to 0. The variable `k` is the index of the next matched character in `string_b`.
2. The method sets `transpositions` to 0.
3. The method examines each character of `string_a` with its index `i`.
4. If `matches_a[i]` is `false`, the method continues with the next character. Only the matched characters are applicable.
5. The line `k += 1 until matches_b[k]` moves `k` forward. The movement stops when `k` points to the next matched character in `string_b`.
6. The method compares the character from `string_a` with the character `string_b[k]`. If the two characters are different, the method adds 1 to `transpositions`.
7. The method adds 1 to `k`. The subsequent search thus starts after the current position.
8. After the loop, the method divides `transpositions` by 2. Ruby does an integer division and removes the fraction.

## The effect of the procedure

Steps 4 and 5 read the matched characters of the two strings in sequence. The result is two lists of characters of the same length. The method compares the two lists position by position.

The two lists hold the same characters. But the sequence of the characters can be different. Each position with two different characters is one error of sequence.

## The division by 2

Two characters in the incorrect sequence cause two errors of sequence. The loop finds the first error when it reads the first character of the pair. It finds the second error when it reads the second character of the pair. The Jaro formula needs the number of pairs, not the number of errors. Thus the method divides the number of errors by 2.

## Example

Compare the names "martha" and "marhta". All six characters match. The matched characters of "martha" are m, a, r, t, h, a. The matched characters of "marhta" are m, a, r, h, t, a. The fourth position gives t against h, which is an error. The fifth position gives h against t, which is the second error. The count of errors is 2, and the method returns 1.

## The use of the result

The method `jaro_similarity` uses the result in the third part of its formula:

```ruby
((matches - transpositions).to_f / matches)
```

Each transposition decreases this part of the score. The formula then calculates the mean value of three parts. Thus a pair of characters in the incorrect sequence decreases the similarity score, but less than a character with no match.

## Limits

- The line `k += 1 until matches_b[k]` has no test for the end of the array. If `matches_b` had fewer `true` items than `matches_a`, `matches_b[k]` would give `nil` after the end of the array. The loop would not stop. The method `count_matches` prevents this condition, because it sets the same number of `true` items in the two arrays.
- Three or more characters in the incorrect sequence can give an odd number of errors. The integer division then removes the fraction. This result agrees with the usual definition of the Jaro similarity.
- The method is correct only for the arrays that `count_matches` supplies. It does not test its inputs.
