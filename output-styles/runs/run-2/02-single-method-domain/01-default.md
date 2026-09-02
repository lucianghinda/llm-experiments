`build_blocks` is at `app/services/edition/draft_query.rb:57`. It's the shared "flatten a list of posts into threads" step that both `bluesky_blocks` (line 40) and `twitter_blocks` (line 54) call, which is why it takes the platform-specific bits as arguments rather than hard-coding them.

## The three parameters

- `records` — an already-loaded array of `Bluesky::Post` or `Twitter::Tweet`, filtered to the edition window and pre-ordered by the DB.
- `timestamp_method` — a symbol, `:post_created_at` or `:tweet_created_at`, since the two tables name their timestamp column differently.
- `thread_key` — a `Method` object (`method(:bluesky_thread_key)` / `method(:twitter_thread_key)`) that answers "which thread does this record belong to?" For Bluesky that's `thread_root_uri.presence || uri` (line 88); for Twitter, `conversation_id.presence || tweet_id` (line 92). A standalone post keys on itself, so it forms a thread of one.

## What it does, step by step

**1. Group into threads** (line 58)

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

Every reply in the same thread produces the same key, so this turns a flat chronological list into an array of thread arrays. `.values` drops the keys — only the membership matters from here.

**2. Order each thread chronologically** (line 59)

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

`&:post_created_at` via `Symbol#to_proc`. The DB already ordered the records and `group_by` preserves insertion order, so this is defensive rather than load-bearing.

**3. Pick the thread's root** (lines 60–62)

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) }
       || ordered_records.first
```

`root_identifier` (line 69) returns the record's *own* id — `uri` for Bluesky, `tweet_id` for Twitter. So the test is "is this record's thread key equal to its own identity?" — true only for the post that started the thread. The `|| ordered_records.first` fallback matters in practice: the real root may not be in `records` at all, because it fell outside the edition window, was `hidden`, or was excluded via `edition_exclusions`. In that case the earliest surviving reply is promoted to root.

**4. Build the block** (line 63)

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is the `Data.define(:root, :thread_members)` at line 4. `thread_members` is the rest of the thread in chronological order. `Array#-` works here because ActiveRecord defines `==`/`hash` on class + id for persisted records.

**5. Sort the blocks** (line 66)

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

`group_by` returned threads in the order their first member appeared, but the chosen root isn't necessarily that first member, so the blocks get re-sorted by their root's timestamp. `public_send` is used here because the value is needed directly rather than as a block argument.

## Where the result goes

`call` (line 10) starts from `empty_sections` — a hash keyed by `Newsletter::SectionTaxonomy.ordered_top_level` — then `add_blocks` (line 78) files each block under `block.root.section`, silently skipping any section key not in the taxonomy. Net effect: **the root post decides the newsletter section for the whole thread**, and within a section, blocks appear ordered by root timestamp.
