The rails MCP tools aren't connected in this session, and the `rails ai:tool` CLI fallback wasn't approved — so the explanation below is based on the file you asked me to read. Where it touches classes outside this file (`Newsletter::SectionTaxonomy`, `Bluesky::Post`, `Twitter::Tweet`, `EditionExclusion`), I mark it as `[ASSUMPTION]`.

## What the class does

`Edition::DraftQuery` takes one `Edition` and returns the draft content for it: a hash of newsletter sections, where each section holds a list of "blocks". A block is one social post plus the rest of its thread.

```ruby
Edition::DraftQuery.new(edition).call
# => { section_key => [DraftBlock, DraftBlock, ...], ... }
```

## The parts, in order

**`DraftBlock`** (line 4) is a small value object made with `Data.define`. It has two fields: `root` (the first/main post) and `thread_members` (the other posts of the same thread, in time order). It is immutable.

**`call`** (lines 10–15) builds an empty hash of sections, then pours Bluesky blocks and Twitter blocks into it. `tap` is used so the hash itself is returned, not the return value of `add_blocks`.

**`empty_sections`** (line 22) asks the taxonomy for the top-level sections in display order, and gives each one an empty array. `index_with { [] }` turns a list of keys into `{key => []}`. Because the keys are inserted in taxonomy order, the resulting hash keeps that order.

**`window`** (line 26) is the time range of the edition. Note the three dots: it is an *exclusive* range. It starts at midnight of `start_date` and ends just before midnight of the day *after* `end_date`. So the whole `end_date` is included, but the next day is not.

**`bluesky_blocks` / `twitter_blocks`** (lines 29–55) are the same recipe twice, once per platform:

1. Start from the organisation's posts (`edition.organisation.bluesky_posts` / `.tweets`).
2. Keep only posts inside the time window and not `hidden`.
3. Drop posts that were explicitly excluded from this edition (`where.not(id: excluded_*_ids)`).
4. `.then { ... }` applies a further filter that drops whole threads whose root was excluded. `then` is used only so the chain stays one expression.
5. `includes(...)` preloads link titles, the author (and the author's platform accounts), and the snapshot image with its blob. This avoids N+1 queries in the view.
6. Order by creation time, then `to_a` to run the query once.
7. Hand the records to `build_blocks`, telling it which timestamp column to use and how to compute a thread key.

`method(:bluesky_thread_key)` wraps a private method into a callable object so it can be passed as an argument.

**`build_blocks`** (lines 57–67) is where posts become threads:

- `group_by` the thread key, so all posts of one conversation land together.
- Sort each group by timestamp.
- Find the record whose thread key equals its own identifier — that is the thread's root. If none is found (for example, the root itself is outside the window or was hidden), fall back to the earliest post in the group.
- Build a `DraftBlock` with that root and the remaining posts.
- Finally sort all blocks by the root's timestamp, oldest first.

**`root_identifier`** (lines 69–76) says what "own identifier" means per platform: `uri` for a Bluesky post, `tweet_id` for a tweet. It returns `nil` for anything else.

**`bluesky_thread_key` / `twitter_thread_key`** (lines 87–93) give the thread key. A reply carries the root's identifier (`thread_root_uri` / `conversation_id`). A standalone post has none, so it uses its own identifier and becomes a group of one. `presence` turns an empty string into `nil` so the fallback also works for blank values.

**`add_blocks`** (lines 78–85) files each block into a section. It reads `block.root.section`, maps it through the taxonomy to a key, and appends. `next unless sections.key?(section_key)` silently skips blocks whose section is not a top-level one — so a block can be dropped from the draft here. Only the *root's* section matters; thread members follow their root.

## The exclusion logic

`edition_exclusions` is a polymorphic join: an edition can exclude specific records. `excluded_records` (line 128) loads the excluded objects for one model class.

There are two levels of exclusion:

- **`excluded_*_ids`** — exclude that single post.
- **`excluded_*_thread_roots`** — if the excluded post *is* the root of its thread (`thread_root_uri == uri`, `conversation_id == tweet_id`), then the whole thread is excluded too. `filter_map` collects the identifier and drops the `nil`s in one pass.

`without_bluesky_root_exclusions` / `without_twitter_root_exclusions` (lines 95–105) return the scope unchanged when there is nothing to exclude. This matters: `where.not(column: [])` in SQL would exclude every row with a non-null value, which is the opposite of what is wanted.

All four exclusion lists are memoized with `@_`-prefixed variables, per the project style. Note that `excluded_records` itself is not memoized, so it runs one query per call — currently four calls total (two per platform).

## Things worth knowing when you change it

- Bluesky and Twitter follow the same shape but keep separate methods, differing only in column names and identifier fields.
- Ordering is decided twice: sections come out in taxonomy order, and blocks inside a section come out oldest-first by root timestamp. The insertion order of `add_blocks` (Bluesky before Twitter) does **not** win — the per-platform lists are appended one after another, so within a section all Bluesky blocks appear before all Twitter blocks, each group sorted by time, but the two groups are not merged into one timeline. If you want a single interleaved timeline per section, you would need to sort after `add_blocks`.
- A thread whose root is missing from the window still shows up, using the earliest available reply as its root.
