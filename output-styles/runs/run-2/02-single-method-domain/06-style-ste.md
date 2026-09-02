# `build_blocks` — what it does

It takes a flat list of social posts and turns it into a list of **threads**. Each thread becomes one `DraftBlock` (a `Data` object with a `root` post and its `thread_members`).

It is generic: both `bluesky_blocks` and `twitter_blocks` call it, passing the platform-specific details as arguments.

## The three parameters

| Parameter | Meaning | Bluesky value | Twitter value |
|---|---|---|---|
| `records` | flat array of posts already loaded from the DB | `Bluesky::Post` array | `Twitter::Tweet` array |
| `timestamp_method` | symbol for the time column | `:post_created_at` | `:tweet_created_at` |
| `thread_key` | a `Method` object that returns the thread id of a record | `bluesky_thread_key` | `twitter_thread_key` |

The `thread_key` methods (lines 87–93) return the thread root id, falling back to the record's own id when the post is not a reply:

- Bluesky: `post.thread_root_uri.presence || post.uri`
- Twitter: `tweet.conversation_id.presence || tweet.tweet_id`

So a standalone post is a thread of one, keyed by itself.

## Step by step (lines 57–67)

**1. Group into threads** — `records.group_by { thread_key.call(record) }.values` gives an array of arrays. Every inner array is one conversation. The hash keys are dropped; only the grouped records matter.

**2. Sort inside the thread** — `ordered_records = thread_records.sort_by(&timestamp_method)` puts the posts of one thread in chronological order. `&:post_created_at` works because the symbol is converted to a proc.

**3. Find the root post:**

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) }
       || ordered_records.first
```

`root_identifier` (lines 69–76) returns the record's *own* id — `uri` for Bluesky, `tweet_id` for Twitter. So the root is the post whose thread key equals its own id, meaning "this post is the start of the thread". If no such post is in the set — for example the real root was excluded, or only replies fall inside the date window — it falls back to the earliest post.

**4. Build the block** — `DraftBlock.new(root: root, thread_members: ordered_records - [root])`. The root is stored separately; `thread_members` holds the remaining replies, still in chronological order.

**5. Sort the blocks** — `blocks.sort_by { |block| block.root.public_send(timestamp_method) }` orders the whole list by each thread's root timestamp. `public_send` is needed here because the symbol is called on a nested object, so `&:symbol` cannot be used.

## How the result is used

`call` (lines 10–15) builds an empty hash of newsletter sections, then `add_blocks` (lines 78–85) files each block under the section of its **root** post (`Newsletter::SectionTaxonomy.for(block.root.section)`). Blocks whose section key is unknown are skipped. The section of a reply does not matter — the root decides where the thread goes.

## Points worth noting

- The grouping runs in Ruby, not SQL. The records are already loaded with `.to_a` and eager-loaded associations, so no extra queries happen here.
- `ordered_records - [root]` uses `Array#-`, which relies on `eql?`/`hash`. For Active Record objects this compares by id, so it removes exactly the root row.
- The method is pure: it does not touch the database or the edition. All exclusion filtering happens earlier, in the scopes at lines 30–38 and 44–52.
