## What it is

`build_blocks` is a small grouping helper shared by both `bluesky_blocks` (line 40) and `twitter_blocks` (line 54). It takes a flat list of posts/tweets and turns it into a list of **threads**, each represented as a `DraftBlock` — a `Data` object holding one `root` and its `thread_members` (line 4).

```ruby
def build_blocks(records, timestamp_method, thread_key)
```

It receives three things so it can work for either platform without knowing which one it is:

| Parameter | Bluesky call | Twitter call |
|---|---|---|
| `records` | array of `Bluesky::Post` | array of `Twitter::Tweet` |
| `timestamp_method` | `:post_created_at` | `:tweet_created_at` |
| `thread_key` | `method(:bluesky_thread_key)` | `method(:twitter_thread_key)` |

`timestamp_method` is a **symbol** (a column name), `thread_key` is a **`Method` object** — a callable that, given a record, returns the id of the thread it belongs to.

## Step by step

**1. Group by thread** (line 58)

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

Every record is asked "which thread are you in?". For Bluesky that is `thread_root_uri.presence || uri` (line 88) — the root URI of the thread, or the post's own URI when the post is standalone. For Twitter it is `conversation_id.presence || tweet_id` (line 92). `group_by` returns a hash keyed by that thread id; `.values` throws the keys away and keeps just the arrays of records, so we now have one array per thread.

**2. Sort each thread chronologically** (line 59)

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

`&:post_created_at` turns the symbol into a block, so this sorts the thread oldest-first by the platform's own timestamp column.

**3. Find the root of the thread** (lines 60–62)

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } || ordered_records.first
```

A record is the root when its thread key equals its own identity. `root_identifier` (line 69) returns `uri` for a Bluesky post and `tweet_id` for a tweet. So the test reads: *"is this record's thread root the record itself?"* That is true for the first post of a thread and for standalone posts.

The `|| ordered_records.first` is the safety net: the real root may not be in `records` at all — it could fall outside the edition's date window (line 26), be `hidden: true`, or be explicitly excluded (lines 32 and 33). In that case the oldest surviving record is promoted to root so the block is still usable.

**4. Build the block** (line 63)

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`thread_members` is everything in the thread except the root, still in chronological order. `Array#-` works on Active Record objects because Active Record defines `hash` and `eql?` in terms of the record's id.

**5. Sort the blocks themselves** (line 66)

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

`group_by` gives no meaningful ordering across groups, so the final list is re-sorted by each thread's **root** timestamp. `public_send` is needed here because the timestamp is a symbol being called on a specific object, not a block converted with `&`.

## Net effect

A flat, chronological list of individual posts goes in; a chronological list of threads goes out, each thread collapsed into one root plus its replies. `call` (line 10) then hands those blocks to `add_blocks`, which files each one into a newsletter section based on `block.root.section` (line 80) — so grouping into a block also decides that the whole thread is placed by its root's section, not by each reply's.
