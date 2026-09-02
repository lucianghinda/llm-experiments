## `count_transpositions` (app/services/authors/match_by_name.rb:108)

This is the second half of a hand-rolled Jaro similarity. It counts how many of the *already-matched* characters are matched but **out of order** between the two strings.

### Preconditions it relies on

It runs only after `count_matches` (line 91), which has filled two parallel boolean arrays:

- `matches_a[i]` — true if `string_a[i]` found a partner in `string_b`
- `matches_b[j]` — true if `string_b[j]` was claimed as a partner

Because `count_matches` sets both flags together on each hit (lines 99–101), the two arrays contain **the same number of `true`s**. That invariant is what makes the walk below safe.

### The walk

```ruby
k = 0
transpositions = 0
string_a.each_char.with_index do |char, i|
  next unless matches_a[i]        # skip unmatched chars in a

  k += 1 until matches_b[k]       # advance k to the next matched char in b
  transpositions += 1 if char != string_b[k]
  k += 1                          # consume that position in b
end
transpositions / 2
```

`i` scans the matched characters of `a` in order; `k` is a persistent cursor that scans the matched characters of `b` in order. Each iteration pairs the *n*-th matched char of `a` with the *n*-th matched char of `b`. If those two characters differ, the pair is out of sequence, so it's counted.

`k` is deliberately declared outside the block — it never rewinds, so the two sequences are zipped positionally in a single linear pass rather than re-scanned.

### Why divide by two

Every genuine swap shows up twice in that scan — once at each of the two positions involved. `martha` vs `marhta`: the `t`/`h` swap produces a mismatch at the 4th matched pair (`t` vs `h`) *and* at the 5th (`h` vs `t`). That's 2 raw mismatches for 1 actual transposition, hence `/ 2`. This is Jaro's `t` term, and the integer division (floor) matches the canonical reference implementations — for cyclic shifts like `abc`/`bca` you get 3 raw mismatches → 1.

### How the result is used

Back in `jaro_similarity` (lines 86–88):

```ruby
((matches / a.length) + (matches / b.length) + ((matches - transpositions) / matches)) / 3.0
```

Transpositions only affect the third term: the fraction of matched characters that are *also* in the right relative order. Continuing the `martha`/`marhta` example — 6 matches, 1 transposition → `(1 + 1 + 5/6) / 3 = 0.944`, which `jaro_winkler` then boosts by the 3-char common prefix `mar` to `0.961`, above the `REVIEW_THRESHOLD` of 0.85.

### One thing worth knowing

`k += 1 until matches_b[k]` has no bounds check. If `matches_b[k]` runs past the end of the array it returns `nil` (falsy) and the loop spins forever incrementing `k`. It's safe here *only* because of the equal-true-count invariant from `count_matches`. If anyone ever changes `count_matches` to set the flags independently, this line becomes an infinite loop rather than an exception — worth a comment or a `while k < matches_b.length` guard if that code is likely to be touched.
