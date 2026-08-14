# How `count_transpositions` works

## What the method does

The method counts the pairs of characters that are in the wrong order.

Two strings can contain the same characters in a different order. The method finds how many
of these order errors are present. It returns one number. A larger number means a larger
difference between the two strings.

The method is one part of the Jaro similarity calculation.

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

The method has four parameters:

- `string_a` is the first string.
- `string_b` is the second string.
- `matches_a` is an array of `true` and `false` values. It has one value for each character
  of `string_a`.
- `matches_b` is an array of `true` and `false` values. It has one value for each character
  of `string_b`.

The method `count_matches` fills the two arrays before this method starts. A `true` value at
position 3 of `matches_a` means this: the character at position 3 of `string_a` has a partner
character in `string_b`. The partner must be near the same position. A `false` value means
that the character has no partner.

The two arrays always contain the same quantity of `true` values. Each match adds one `true`
value to each array. This method uses that fact.

## The two variables

The method uses two variables:

- `transpositions` counts the errors. It starts at 0.
- `k` is a position number in `string_b`. It also starts at 0.

The variable `k` moves through `string_b`. It stops only at the positions that have a match.
It goes over the positions that have no match.

## The steps in the loop

The loop goes through the characters of `string_a` from left to right. The variable `char`
holds the current character. The variable `i` holds the position of that character.

For each character, the method does these steps:

1. It looks at `matches_a[i]`. If the value is `false`, the character has no partner. The
   method goes to the next character. The line `next unless matches_a[i]` does this.
2. It moves `k` forward until `matches_b[k]` is `true`. The line `k += 1 until matches_b[k]`
   does this. After this step, `k` shows the next matched character in `string_b`.
3. It compares `char` with `string_b[k]`. These are two matched characters at the same
   place in their sequences. If the two characters are different, the method adds 1 to
   `transpositions`.
4. It moves `k` forward by one position. The next loop pass must start after the character
   that it used.

The result is this: the method compares the matched characters of `string_a` with the matched
characters of `string_b`, in order. The first matched character of `string_a` goes with the
first matched character of `string_b`. The second goes with the second, and so on. The
positions of the characters in the full strings are not important here. Only the sequence of
the matches is important.

Step 2 is safe because the two arrays hold an equal quantity of `true` values. The method
always finds a matched position in `string_b` for each matched position in `string_a`.
Therefore `k` cannot move past the end of the array.

## Why the method divides by two

The last line is `transpositions / 2`.

Two characters are in the wrong order together. If the character of `string_a` is different
from the character of `string_b` at one place, then a second place also has a difference. The
loop counts both places. Each order error therefore gives a count of 2.

The division by 2 changes the quantity of wrong characters into the quantity of wrong pairs.

Ruby uses integer division here. The result has no decimal part.

## An example

Compare `MARTHA` with `MARHTA`.

All six characters of `MARTHA` find a partner in `MARHTA`. The two arrays contain only `true`
values.

The loop compares the characters in this sequence:

| Position | `string_a` | `string_b` | Result       |
|---|---|---|---|
| 1 | M | M | equal        |
| 2 | A | A | equal        |
| 3 | R | R | equal        |
| 4 | T | H | different    |
| 5 | H | T | different    |
| 6 | A | A | equal        |

The count is 2. The method returns `2 / 2`, which is 1. The two strings have one pair of
characters in the wrong order.

## Where the result goes

The method `jaro_similarity` uses the result in this part of its formula:

```ruby
(matches - transpositions).to_f / matches
```

A larger quantity of transpositions makes this part smaller. A smaller value gives a lower
similarity score. The class uses that score to find the author name that is nearest to the
name that the user supplies.
