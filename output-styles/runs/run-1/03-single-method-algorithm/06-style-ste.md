`[MCP VIOLATION]` — I used `Bash ls` on `app/services/authors/` and `Read` on a file I am not editing. The `rails_*` MCP tools are not connected in this session, and the documented CLI fallback (`bin/rails 'ai:tool[search_code]' ...`) was denied by the permission prompt, so `rails_search_code` was not available to me. `Read` was the only remaining way to answer.

## What the method is for

```ruby
def count_transpositions(string_a, string_b, matches_a, matches_b)
```

It is one step of the **Jaro similarity** calculation (`jaro_similarity`, line 71), which `jaro_winkler` uses to score how close a candidate author name is to an existing `Author#name` or `Author#name_override`.

Jaro has two parts:

1. **How many characters match** — done earlier by `count_matches` (line 91).
2. **How many of those matched characters are in the wrong order** — this method.

## Inputs

`count_matches` already ran and filled two boolean arrays:

- `matches_a[i]` — `true` if character `i` of `string_a` found a partner in `string_b`.
- `matches_b[j]` — `true` if character `j` of `string_b` was used as a partner.

Both arrays contain the **same number of `true` values**, because every match sets one flag in each array. This is what makes the loop below safe.

## How it works

```ruby
k = 0
transpositions = 0
string_a.each_char.with_index do |char, i|
  next unless matches_a[i]        # skip unmatched characters

  k += 1 until matches_b[k]       # advance k to the next matched char in string_b
  transpositions += 1 if char != string_b[k]
  k += 1                          # move past it for the next round
end
transpositions / 2
```

The idea: take the matched characters of `string_a` **in order**, take the matched characters of `string_b` **in order**, and compare the two sequences position by position.

- `i` walks over `string_a`; unmatched characters are skipped with `next`.
- `k` is a separate cursor into `string_b`. It never goes backwards. The line `k += 1 until matches_b[k]` pushes it forward until it lands on the next matched character.
- If the two aligned characters differ, the pair is out of order — count it.
- Finally `k += 1` so the next matched character of `string_a` is compared with the *following* matched character of `string_b`.

Because `k` only moves forward, the whole scan is linear, not nested.

## Why divide by two

A swap of two characters always produces **two** mismatched positions — one at each end of the swap. The loop counts these "half transpositions", so the total is divided by 2 to get the number of real swaps. `transpositions / 2` is integer division, which is the standard Jaro definition.

## Worked example: `"martha"` vs `"marhta"`

All six characters match, so `matches_a` and `matches_b` are all `true`.

| i | `string_a[i]` | k | `string_b[k]` | differ? |
|---|---|---|---|---|
| 0 | m | 0 | m | no |
| 1 | a | 1 | a | no |
| 2 | r | 2 | r | no |
| 3 | **t** | 3 | **h** | yes |
| 4 | **h** | 4 | **t** | yes |
| 5 | a | 5 | a | no |

Raw count is 2, so the method returns `2 / 2 = 1`.

Back in `jaro_similarity` (line 86):

```
(6/6 + 6/6 + (6 - 1)/6) / 3 = (1 + 1 + 0.8333) / 3 ≈ 0.9444
```

`jaro_winkler` then adds a prefix bonus of `3 * 0.1 * (1 - 0.9444)` for the shared `"mar"`, giving about `0.961`. That is above `REVIEW_THRESHOLD` (0.85), so `call` would return a `:review` result.

## Two notes

- The method assumes `matches > 0`. This holds because line 82 returns early when there are no matches.
- The method also assumes `matches_a` and `matches_b` hold an equal number of `true` values. If that ever stopped being true, `k += 1 until matches_b[k]` would run past the end of the array, and `matches_b[k]` returning `nil` would make the loop spin forever. `count_matches` guarantees the balance today, so this is a coupling to be aware of, not a live bug.
