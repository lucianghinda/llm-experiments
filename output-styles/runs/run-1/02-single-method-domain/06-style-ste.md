## `build_blocks` — what it does

`app/services/edition/draft_query.rb:57`

It takes a flat list of social posts and turns them into **threads**. Each thread becomes one `DraftBlock` — a root post plus its replies.

### Parameters

| Name | Meaning |
|---|---|
| `records` | Flat array of posts, already loaded and ordered |
| `timestamp_method` | Symbol for the time column: `:post_created_at` (Bluesky) or `:tweet_created_at` (Twitter) |
| `thread_key` | A `Method` object that returns the thread id of a record |

The last two parameters exist because Bluesky and Twitter use different column names. The caller passes `method(:bluesky_thread_key)` (line 40) or `method(:twitter_thread_key)` (line 54), so the grouping logic stays shared.

### Step by step

**1. Group into threads** (line 58)

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`thread_key` falls back to the record's own id when there is no thread parent:

- Bluesky: `post.thread_root_uri.presence || post.uri` (line 88)
- Twitter: `tweet.conversation_id.presence || tweet.tweet_id` (line 92)

So a standalone post forms a group of one. A thread of five posts forms a group of five, because all five share the same root uri / conversation id. `.values` drops the keys and keeps only the arrays of records.

**2. Sort inside each thread** (line 59)

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

Oldest first. `&:post_created_at` style — the symbol is turned into a block.

**3. Find the root** (lines 60–62)

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } || ordered_records.first
```

A record is the root when its thread key equals its **own** identifier (`record.uri` for Bluesky, `record.tweet_id` for Twitter — see `root_identifier`, line 69). In other words: "this post points at itself as the thread root."

The `|| ordered_records.first` is the safety net. The real root may be missing from `records` — it can be hidden, excluded by an `EditionExclusion`, or outside the date `window`. In that case the oldest surviving post is promoted to root.

**4. Build the block** (line 63)

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a `Data` object (line 4). `thread_members` is every other post in the thread, still in time order. Note `ordered_records - [root]` uses `Array#-`, which removes by equality — for Active Record objects this matches on the same id, so only the root is removed.

**5. Sort the blocks** (line 66)

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

Threads are ordered by the time of their root post. `public_send` is needed here because `timestamp_method` is a symbol, not a block.

### Where the result goes

`call` (line 10) builds an empty hash of newsletter sections, then `add_blocks` (line 78) files each block under the section of its **root** post. Replies do not get their own section — the root decides for the whole thread. Blocks whose section is not a known top-level key are dropped silently (line 81).

### Small note

Step 3 calls `thread_key.call(record)` again for each record, after `group_by` already computed it in step 1. Harmless — the methods are cheap attribute reads — but the key is available as the hash key if you ever want to skip the recomputation.
