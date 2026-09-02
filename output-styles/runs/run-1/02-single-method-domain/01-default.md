`build_blocks` (app/services/edition/draft_query.rb:57) is the shared grouping step for both platforms. Its job: take a flat list of posts/tweets and collapse them into thread-shaped "blocks" ordered chronologically.

## The signature

```ruby
def build_blocks(records, timestamp_method, thread_key)
```

It's a small polymorphism shim. `Bluesky::Post` and `Twitter::Tweet` don't share an interface for "when was this posted" or "what thread is this in", so the two callers inject that:

- Bluesky (line 40): `:post_created_at` + `method(:bluesky_thread_key)` → `thread_root_uri.presence || uri`
- Twitter (line 54): `:tweet_created_at` + `method(:twitter_thread_key)` → `conversation_id.presence || tweet_id`

`thread_key` arrives as a `Method` object, hence the `.call(record)` rather than `.()`-free symbol usage; `timestamp_method` arrives as a Symbol, used both via `&` (Symbol#to_proc, line 59) and `public_send` (line 66).

## Step by step

**1. Group into threads** — `records.group_by { thread_key.call(record) }.values` buckets records by thread identity. A standalone post falls back to its own `uri`/`tweet_id`, so it forms a bucket of one. A reply chain shares the root's URI / the conversation id, so it forms one bucket.

**2. Order within the thread** — `ordered_records = thread_records.sort_by(&timestamp_method)`, oldest first.

**3. Pick the root:**

```ruby
root = ordered_records.find { |r| thread_key.call(r) == root_identifier(r) } || ordered_records.first
```

`root_identifier` (line 69) returns the record's *own* identity — `uri` for Bluesky, `tweet_id` for Twitter. So the condition "my thread key equals my own id" is true exactly for the post that starts the thread (and trivially true for a standalone post, whose key already fell back to its own id). Replies have a thread key pointing at someone else's id, so they don't match.

The `|| ordered_records.first` is the orphan fallback: if the actual root isn't in the result set — outside the edition's date window, `hidden: true`, or individually excluded — the oldest surviving reply is promoted to root so the block still renders.

**4. Build the value object** — `DraftBlock.new(root:, thread_members: ordered_records - [root])` (a `Data` type defined at line 4). `thread_members` is everything except the root, still oldest-first. `Array#-` works here because ActiveRecord defines `==`/`hash` on the primary key.

**5. Sort blocks** — `blocks.sort_by { |block| block.root.public_send(timestamp_method) }`. The per-record ordering from the SQL query is lost by `group_by`, so blocks are re-sorted by their root's timestamp. Note this is the *root's* time, not the thread's latest activity — an old thread with a new reply still sorts by the old root.

## How it fits the rest

`call` (line 10) starts from `empty_sections` — every top-level `Newsletter::SectionTaxonomy` key mapped to `[]` — then `add_blocks` files each block into the section derived from `block.root.section`, silently dropping blocks whose section isn't a known top-level key (line 81). So the section of the whole thread is decided by whichever record `build_blocks` chose as root — which, in the orphan case above, may be a reply rather than the real thread starter.

One asymmetry worth knowing: excluding a record via `edition_exclusions` normally just drops that one record (`where.not(id: ...)`), but if the excluded record *is* a thread root (lines 111–115 / 121–125), `without_*_root_exclusions` drops the entire thread before `build_blocks` ever sees it.
