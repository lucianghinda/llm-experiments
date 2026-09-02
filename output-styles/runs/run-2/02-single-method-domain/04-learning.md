`app/services/edition/draft_query.rb:57` — here's what it does, step by step.

## Purpose

`build_blocks` takes a flat list of social posts and folds them into **threads**. Each thread becomes a `DraftBlock` (the `Data.define` at line 4) with one `root` post and the rest as `thread_members`. It's called twice — once for Bluesky (line 40), once for Twitter (line 54) — with different "how do I identify a thread" strategies.

## The three parameters

```ruby
def build_blocks(records, timestamp_method, thread_key)
```

- `records` — already-loaded array (note the `.to_a` at lines 38/52, so all of this is in-memory Ruby, no more SQL)
- `timestamp_method` — a **Symbol**: `:post_created_at` or `:tweet_created_at`
- `thread_key` — a **Method object**: `method(:bluesky_thread_key)` or `method(:twitter_thread_key)`

Those last two are the only things that differ between the two platforms. Everything else in the method is platform-agnostic.

## Step 1 — group into threads

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`thread_key` resolves to (line 88): `post.thread_root_uri.presence || post.uri`. So:
- A **reply** in a thread returns the root's URI.
- A **standalone post** has no `thread_root_uri`, so it returns its own URI.

Every post in the same thread therefore produces the same string, and `group_by` collects them. A standalone post becomes a group of one. `.values` discards the keys — we only need the buckets.

## Step 2 — order within the thread

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

`&:post_created_at` — `Symbol#to_proc` turns the symbol into the accessor block. Oldest first, so the thread reads in reply order.

## Step 3 — find the root (the clever bit)

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end || ordered_records.first
```

`root_identifier` (line 69) returns the record's **own** id — `uri` for Bluesky, `tweet_id` for Twitter. So the condition reads: *"is this record's thread key the same as its own identity?"* That's true for exactly one post in a thread — the one that started it, since it either has no `thread_root_uri` or has one pointing at itself.

The `|| ordered_records.first` fallback matters more than it looks. The query filters by date window and `hidden: false` (lines 31, 45), so the actual root post may not be in `records` at all — the thread might have started before the edition's window. In that case there is no self-matching record, and the earliest surviving reply is promoted to root.

## Step 4 — build and sort

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
...
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

`Array#-` removes the root from its own member list. Because `timestamp_method` is a Symbol rather than a block here, it needs `public_send` to invoke it dynamically.

The final sort is what makes the newsletter draft read chronologically: threads are ordered by **when they started**, not by when their most recent reply landed. A thread begun Monday that gets replies Friday still appears in Monday's position.

Downstream, `add_blocks` (line 78) reads `block.root.section` — so the root post alone decides which newsletter section the entire thread lands in.

`★ Insight ─────────────────────────────────────`
- **`Method` objects as strategy injection.** `method(:bluesky_thread_key)` grabs a bound method and passes it like a lambda. It's a lighter alternative to defining a `ThreadKeyStrategy` class — you get polymorphism without a new object graph, and `thread_key.call(record)` reads the same regardless of platform. The cost is that `build_blocks` can't be understood without jumping to both callers to see what gets passed.
- **`Data.define` for a read-only value object.** `DraftBlock` (line 4) is Ruby 3.2+ `Data`, not `Struct` — immutable, keyword-init only, no accidental `block.root = ...` in a view. Good fit for something that only travels from query → template.
- **Self-referencing root detection.** `thread_key(r) == root_identifier(r)` is a neat trick: instead of storing a separate `is_root` flag, rootness is derived from the data already there. It also degrades gracefully — when the root is outside the date window, the `||` fallback keeps the thread renderable instead of dropping it.
- **`.to_a` is the boundary marker.** Lines 38 and 52 deliberately materialize the relation before `build_blocks`, so all grouping/sorting is Ruby, not SQL. Combined with the `includes` above it, that's what keeps `add_blocks` calling `block.root.section` without N+1s.
`─────────────────────────────────────────────────`
