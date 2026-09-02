## `build_blocks` — what it does

```ruby
def build_blocks(records, timestamp_method, thread_key)
```

It takes a **flat list** of social posts and turns it into a **sorted list of threads**. It is written once and reused by both `bluesky_blocks` (line 40) and `twitter_blocks` (line 54), which is why the two platform-specific details are passed in as arguments:

| Argument | Bluesky | Twitter |
|---|---|---|
| `timestamp_method` (a Symbol) | `:post_created_at` | `:tweet_created_at` |
| `thread_key` (a `Method` object) | `bluesky_thread_key` → `thread_root_uri` or `uri` | `twitter_thread_key` → `conversation_id` or `tweet_id` |

### Step by step

**1. Group the records into threads**

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

Every record is asked for its thread key. For a reply, that key is the id of the thread it belongs to; for a standalone post, `presence ||` falls back to the post's *own* id (lines 88 and 92). So all posts of one conversation land in the same group, and a lone post becomes a group of one. `.values` drops the keys and keeps only the arrays of grouped records.

**2. Sort inside each thread**

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

Oldest first, using whichever timestamp column the platform uses.

**3. Find the root post of the thread**

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } || ordered_records.first
```

The root is the record that **points at itself**: its thread key equals its own identifier (`uri` for Bluesky, `tweet_id` for Twitter — see `root_identifier`, line 69). A reply fails this test, because its thread key points at a different post.

The `|| ordered_records.first` is the safety net. The real root may not be present in `records` — it can be hidden, excluded, or created outside the edition's date `window`. In that case the oldest surviving record is promoted to root, so a thread is never left without one.

**4. Wrap it in a value object**

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a `Data` class (line 4) with two fields: the root, and the remaining posts of the thread in chronological order. `ordered_records - [root]` is array subtraction, so the root is not repeated inside `thread_members`.

**5. Sort the blocks against each other**

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

`public_send` is needed here because `timestamp_method` is a Symbol chosen at runtime. Threads are ordered by the time of their **root**, not by their newest reply — so a thread appears in the draft at the moment it started.

### The result

An array of `DraftBlock`s, ordered oldest-to-newest. `add_blocks` (line 78) then files each block into a newsletter section, using only the root's `section` — the whole thread follows its root.
