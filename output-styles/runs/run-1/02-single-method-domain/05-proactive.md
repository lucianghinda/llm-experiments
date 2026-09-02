## `build_blocks` (app/services/edition/draft_query.rb:57)

It's the platform-agnostic step that turns a flat list of social posts into thread-grouped `DraftBlock`s, ordered chronologically. Both `bluesky_blocks` and `twitter_blocks` funnel into it, passing the bits that differ per platform:

- `records` — the already-filtered, already-sorted array of `Bluesky::Post` or `Twitter::Tweet`
- `timestamp_method` — the symbol naming the time column (`:post_created_at` vs `:tweet_created_at`)
- `thread_key` — a `Method` object (`method(:bluesky_thread_key)` / `method(:twitter_thread_key)`) that answers "which thread does this record belong to?"

That last one is the interesting piece of design: the caller injects the platform difference as a callable, so `build_blocks` never branches on class.

### Step by step

**1. Group into threads** (line 58)

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`bluesky_thread_key` returns `post.thread_root_uri.presence || post.uri`; `twitter_thread_key` returns `tweet.conversation_id.presence || tweet.tweet_id`. So a reply carries its root's identifier, and a standalone post falls back to its own — meaning a standalone post becomes a one-element group. `.values` discards the keys; only the buckets matter from here.

**2. Order within the thread** (line 59)

`ordered_records = thread_records.sort_by(&timestamp_method)` — oldest first. `&:post_created_at` works because the symbol is converted to a proc.

**3. Pick the root** (lines 60–62)

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } || ordered_records.first
```

The root is the record whose *thread key* equals its *own* identifier (`uri` for Bluesky, `tweet_id` for Twitter) — i.e. the post that starts the thread. The `|| ordered_records.first` is the fallback for when the actual root isn't in the result set: it may have been hidden, outside the edition's date window, or explicitly excluded. In that case the earliest surviving reply is promoted to root so the block still renders.

**4. Build the block** (line 63)

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a `Data.define(:root, :thread_members)` (line 4). `thread_members` is everything else in chronological order — an empty array for a standalone post. Note `Array#-` removes by `==`, which for Active Record records means same class + same id, so exactly the one root is dropped.

**5. Sort the blocks** (line 66)

`blocks.sort_by { |block| block.root.public_send(timestamp_method) }` — threads are ordered by their root's timestamp. `public_send` is needed here because it's a dynamic call on `block.root` rather than on the array element, so the `&symbol` shorthand from step 2 doesn't apply.

### Where the result goes

`call` builds a hash of empty section arrays from `Newsletter::SectionTaxonomy.ordered_top_level`, then `add_blocks` (line 78) files each block under `block.root.section` — so the root post alone decides which newsletter section the whole thread lands in, and blocks whose section isn't a known top-level key are silently dropped (line 81).

One consequence worth knowing: because grouping happens in Ruby after the query, the exclusion logic upstream has to work in two passes — `excluded_*_ids` drops individual posts, while `excluded_*_thread_roots` (lines 111–125) drops entire threads when the excluded record *is* a root. Without that second pass, excluding a thread root would just cause step 3's fallback to promote a reply and the thread would reappear.
