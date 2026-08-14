# The method count_transpositions

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

## 1. Purpose

The method `count_transpositions` counts the characters that are in the wrong
order. It is one step of the Jaro similarity calculation in the class
`Authors::MatchByName`. The Jaro calculation uses this count to decrease the
score of a name.

## 2. Technical names

This description uses these technical names:

- string_a: the first text.
- string_b: the second text.
- match: a character that is in the two texts and that is near to the same
  position.
- transposition: two matches that are in a different order in the two texts.

## 3. The inputs

The method has four inputs:

- string_a and string_b: the two texts.
- matches_a: a list of true values and false values. The list has one value
  for each character of string_a.
- matches_b: a list of the same type for string_b.

The method `count_matches` makes the two lists first. A value is true when the
character at that position is a match. The two lists always contain the same
number of true values.

## 4. The variables

The method uses two variables:

- k: the position in string_b of the next match. The start value is 0.
- transpositions: the number of the differences. The start value is 0.

## 5. The steps

The method examines each character of string_a. It starts at the first
position. For each character, the method does these steps:

1. If the value in matches_a at this position is false, go to the next
   character.
2. If the value is true, increase k until the value in matches_b at position k
   is true.
3. Compare the character from string_a with the character in string_b at
   position k.
4. If the two characters are different, add 1 to transpositions.
5. Add 1 to k.

Step 2 moves k to the next match in string_b. Step 5 moves k after that match.
Thus step 2 can find the subsequent match.

The steps make pairs of the matches. The first match of string_a goes with the
first match of string_b. The second match of string_a goes with the second
match of string_b. The method uses the same procedure for all the matches.

## 6. The result

The last operation divides transpositions by 2. This division is necessary
because one change of the order makes two differences.

Example: the two texts are MARTHA and MARHTA.

- All six characters are matches.
- At the position of T in MARTHA, string_b has H.
- At the position of H in MARTHA, string_b has T.
- The number of the differences is 2, but there is only one transposition.
- The result is 2 divided by 2. Thus the result is 1.

Usually the number of the differences is an even number. But three or more
matches can be in a different sequence. Then the number is an odd number. Ruby
divides two integers and gives an integer. Thus Ruby removes the fraction part
of the result. This behavior agrees with the standard Jaro algorithm.

## 7. Conditions and limits

- The method gives a correct result only when matches_a and matches_b contain
  the same number of true values. The method `count_matches` makes this
  condition true.
- Step 2 has no limit for k. If matches_b contains fewer true values than
  matches_a, k becomes larger than the length of matches_b. Then the value
  `matches_b[k]` is nil, and step 2 does not stop. Thus the two lists must not
  change after the method `count_matches`.
- The method `jaro_similarity` calls `count_transpositions` only when the
  number of the matches is more than 0.
- The method `jaro_winkler` makes the two texts lower case first. Thus this
  method does not compare the case of the characters.
