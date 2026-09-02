`count_transpositions` is at `app/services/authors/match_by_name.rb:108`. Here is the explanation in ASD-STE100 Simplified Technical English.

## What the method does

The method counts the transpositions between two strings. A transposition is a pair of matched letters that are in a different sequence in the two strings.

The method is a part of the Jaro similarity calculation (`app/services/authors/match_by_name.rb:71`). The app uses this calculation to compare an author name with the names in the database.

## The inputs

The method gets four inputs:

- `string_a` and `string_b` are the two strings.
- `matches_a` and `matches_b` are two arrays of true/false values. The method `count_matches` (line 91) makes these arrays before. If `matches_a[i]` is true, the letter at position `i` in `string_a` has a match in `string_b`.

## The procedure

1. The method sets the counter `k` to 0. The counter `k` shows the position in `string_b`.
2. The method sets `transpositions` to 0.
3. The method reads each letter of `string_a` in sequence.
4. If the letter has no match, the method goes to the subsequent letter. It does not do steps 5 to 8.
5. If the letter has a match, the method moves `k` forward. It moves `k` forward until `k` shows a matched letter in `string_b`.
6. The method compares the letter from `string_a` with the letter at position `k` in `string_b`.
7. If the two letters are different, the method adds 1 to `transpositions`.
8. The method adds 1 to `k`. Thus the subsequent comparison starts after this position.
9. At the end, the method divides `transpositions` by 2. It gives this result to the caller.

## Why the method divides by 2

The method compares the matched letters of the two strings in sequence. If two letters are in a different sequence, the method finds a difference two times: one time at each of the two positions. Thus one transposition makes a count of 2. The division by 2 gives the correct number of transpositions.

The division uses integer arithmetic. Ruby removes the fraction. Thus `3 / 2` gives 1.

## An example

Compare `martha` with `marhta`.

- All six letters have a match.
- The matched letters of `martha` are `m a r t h a`.
- The matched letters of `marhta` are `m a r h t a`.
- The letters at position 4 and position 5 are different: `t`/`h` and `h`/`t`.
- The count of differences is 2. The method divides 2 by 2. The result is 1 transposition.

## An important condition

The loop at line 114 (`k += 1 until matches_b[k]`) has no upper limit for `k`. The loop is safe only because `matches_a` and `matches_b` always contain the same number of true values. `count_matches` makes this condition true, because it sets one value in each array at the same time (lines 99 and 100). Thus a matched letter in `string_b` is always available.
