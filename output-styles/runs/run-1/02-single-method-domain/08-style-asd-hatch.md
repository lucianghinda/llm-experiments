I read `app/services/edition/draft_query.rb` directly. The project's `rails_*` MCP tools are not connected in this session, and the CLI fallback command needs approval, so `Read` was the only way to answer.

## `build_blocks` — app/services/edition/draft_query.rb:57

The method changes a flat list of social posts into a list of **threads**. Each thread becomes one `DraftBlock` (a `Data` type with a `root` and its `thread_members`, line 4).

It is platform-agnostic. Both callers use it — `bluesky_blocks` (line 40) and `twitter_blocks` (line 54) — and they give it the platform-specific parts as arguments:

| Parameter | Bluesky | Twitter |
|---|---|---|
| `records` | posts in the edition window | tweets in the edition window |
| `timestamp_method` | `:post_created_at` | `:tweet_created_at` |
| `thread_key` | `method(:bluesky_thread_key)` → `thread_root_uri` or `uri` | `method(:twitter_thread_key)` → `conversation_id` or `tweet_id` |

### The steps

**1. Group into threads (line 58).**
`records.group_by { thread_key.call(record) }.values` puts all records that have the same thread key into the same array. The key is the thread root: for a reply it is the root post; for a standalone post it is the post itself. So each array is one conversation.

**2. Sort each thread in time order (line 59).**
`sort_by(&timestamp_method)` puts the records of the thread from oldest to newest. `&:post_created_at` / `&:tweet_created_at` comes from the symbol that the caller supplied.

**3. Find the root of the thread (lines 60–62).**

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } || ordered_records.first
```

A record is the root when its thread key is equal to its own identifier — `uri` for a `Bluesky::Post`, `tweet_id` for a `Twitter::Tweet` (`root_identifier`, line 69). In other words: *the post points at itself as the thread root.*

If no such record exists, the method uses `ordered_records.first`, the oldest record. This fallback is important: the true root post can be absent from the result set, because it is outside the date window, hidden, or excluded from the edition (lines 31–33). Then the earliest reply becomes the visible root.

**4. Build the block (line 63).**
`DraftBlock.new(root: root, thread_members: ordered_records - [root])`. The members are the other records of the thread, still in time order. `Array#-` compares with Active Record equality (same class, same `id`), so it removes only the root record.

**5. Sort the blocks (line 66).**
`blocks.sort_by { |block| block.root.public_send(timestamp_method) }` puts the threads in chronological order by their root. The order after `group_by` is the order of first occurrence, so this final sort makes the result deterministic.

### What the caller does next

`call` (line 10) sends both block lists to `add_blocks` (line 78). That method reads `block.root.section`, maps it through `Newsletter::SectionTaxonomy`, and pushes the block into the matching newsletter section. So the **root decides the section for the whole thread** — the replies follow their root.

**One thing to know:** `sort_by` in Ruby is not stable. If two records in a thread share the same timestamp, their relative order can change between runs. It matters only if the fallback on line 62 must select a root from tied records.
