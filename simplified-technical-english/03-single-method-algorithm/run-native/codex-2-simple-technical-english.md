The method counts matched characters that appear in a different order.

It receives two strings and two arrays. Each array marks which characters were matched earlier.

The method does this:

1. It reads the matched characters in `string_a`.
2. It uses `k` to find the next matched character in `string_b`.
3. It compares the two characters.
4. If the characters are different, it adds 1 to `transpositions`.
5. It moves to the next matched character in `string_b`.

One real transposition causes two character differences. For example, `TH` and `HT` have two differences but one transposition. Therefore, the method divides the result by 2 before it returns it.
