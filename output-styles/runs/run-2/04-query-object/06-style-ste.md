## What it does

`Edition::DraftQuery` builds the draft content of a newsletter edition. It takes one `Edition`, collects the Bluesky posts and tweets that belong to that edition's date window, groups them into threads, and sorts them into newsletter sections.

Entry point:

```ruby
Edition::DraftQuery.new(edition).call
# => { section_key => [DraftBlock, ...], ... }
```

## The unit of output: `DraftBlock`

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A block is one social-media thread: the `root` (first/head post) plus `thread_members` (the rest of the thread, in time order, root removed). A single stand-alone post becomes a block with an empty `thread_members`.

## Step by step

**1. Empty sections (`empty_sections`, line 21)**

`Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }` creates an ordered hash: every top-level section key maps to an empty array. Section order is therefore fixed by the taxonomy, not by the data.

**2. Date window (`window`, line 25)**

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

An exclusive range. Using `end_date.tomorrow.beginning_of_day` with `...` makes the whole `end_date` day inclusive, while avoiding the `23:59:59` edge problem.

**3. Fetching records (`bluesky_blocks` / `twitter_blocks`, lines 29–55)**

The two methods are the same shape, only the column and model names differ:

- scope to the edition's organisation (`bluesky_posts` / `tweets`)
- filter by the time window and `hidden: false`
- remove records excluded by id
- remove whole threads whose root was excluded
- eager-load `:url_titles`, the nested author chain, and the snapshot image attachment + blob (avoids N+1)
- order by creation time, then `to_a` (all further work is in Ruby)

**4. Exclusions (lines 95–129)**

`edition.edition_exclusions` is a polymorphic list of things the editor removed from this edition. `excluded_records(model)` loads the excluded objects for one type.

There are two levels:

- `excluded_bluesky_ids` / `excluded_twitter_ids` — drop those single records.
- `excluded_*_thread_roots` — if the excluded record *is itself a thread root* (`thread_root_uri == uri`, or `conversation_id == tweet_id`), then the whole thread is dropped, not just the root post.

`without_bluesky_root_exclusions` / `without_twitter_root_exclusions` return the scope unchanged when the exclusion list is empty, so no useless `NOT IN ()` clause is added.

**5. Grouping into threads (`build_blocks`, line 57)**

The thread key is platform-specific:

- Bluesky: `thread_root_uri` if present, else the post's own `uri`
- Twitter: `conversation_id` if present, else the tweet's own `tweet_id`

So a reply keys to its thread; a stand-alone post keys to itself.

Records are grouped by that key. Inside each group:

1. sort by timestamp;
2. find the record whose own identifier equals the thread key — that is the true root;
3. if no such record is in the set (for example the root was outside the date window), fall back to the earliest record;
4. build a `DraftBlock`, with the root removed from `thread_members`.

Finally blocks are sorted by the root's timestamp.

**6. Placing blocks in sections (`add_blocks`, line 78)**

For each block, the root's `section` value is mapped through `Newsletter::SectionTaxonomy.for(...)` to a key, then the block is appended to that section's array. `next unless sections.key?(section_key)` silently skips a block whose key is not a top-level section — worth knowing, because such content disappears from the draft without any warning.

Bluesky blocks are added before Twitter blocks (line 12–13), so inside one section Bluesky content comes first; the two platforms are **not** merged and re-sorted by time.

## Notes

- `[ASSUMPTION]` I did not verify `Newsletter::SectionTaxonomy`, `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`, or the `Bluesky::Post` / `Twitter::Tweet` columns in this project — my description of them comes from how this file uses them.
- Small inefficiency: `excluded_records` runs a fresh query each time. `excluded_bluesky_ids` and `excluded_bluesky_thread_roots` each call it, so the same rows are loaded twice per platform (four queries where two would do). Memoizing `excluded_records` per model would fix it.
