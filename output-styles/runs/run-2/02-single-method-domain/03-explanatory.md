Here's how `build_blocks` (app/services/edition/draft_query.rb:57) works.

## Purpose

A newsletter edition shouldn't list every Bluesky post and tweet as a separate item — a 5-post thread is *one* story. `build_blocks` collapses a flat, chronologically-ordered list of records into a list of `DraftBlock` value objects, each holding one `root` record plus its `thread_members` (the replies).

## The signature is deliberately platform-agnostic

```ruby
def build_blocks(records, timestamp_method, thread_key)
```

Both `bluesky_blocks` (line 40) and `twitter_blocks` (line 54) call it, passing the bits that differ between platforms:

| Param | Bluesky | Twitter |
|---|---|---|
| `timestamp_method` (Symbol) | `:post_created_at` | `:tweet_created_at` |
| `thread_key` (Method object) | `method(:bluesky_thread_key)` | `method(:twitter_thread_key)` |

`method(:bluesky_thread_key)` grabs the private method as a first-class `Method` object, which responds to `.call`. Inside `build_blocks` nothing knows or cares which platform it's handling — it just calls `thread_key.call(record)`.

`★ Insight ─────────────────────────────────────`
- Passing a `Method` object instead of a symbol is what lets one method serve two models with genuinely different column names — `thread_root_uri`/`uri` vs `conversation_id`/`tweet_id`. It's dependency injection at method granularity, cheaper than an adapter class.
- `Data.define(:root, :thread_members)` (line 4) creates an immutable value object — no `attr_writer`, structural equality, keyword init. It's the right shape for a query result that views only read.
`─────────────────────────────────────────────────`

## Step 1 — Group into threads

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

The thread key is *the thread's root identifier*, with a fallback to the record's own id:

```ruby
def bluesky_thread_key(post) = post.thread_root_uri.presence || post.uri
def twitter_thread_key(tweet) = tweet.conversation_id.presence || tweet.tweet_id
```

So a standalone post (no `thread_root_uri`) keys on its own `uri` and forms a group of one. A thread's root and all its replies share the same key and land in the same group. `.values` discards the keys — from here on only the groupings matter.

## Step 2 — Order within the thread, then pick the root

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } || ordered_records.first
```

`sort_by(&:post_created_at)` — the `&` on a Symbol becomes a block calling that method on each element. (The SQL already applied `order(:post_created_at)` and `group_by` preserves insertion order, so this re-sort is redundant in practice; it makes the method correct standalone regardless of how `records` arrived.)

The root test is: **does this record's thread key point at itself?** `root_identifier` (line 69) returns `record.uri` for a `Bluesky::Post` and `record.tweet_id` for a `Twitter::Tweet`. The root of a thread is the post whose `thread_root_uri` *is* its own `uri` — so `thread_key.call(record) == root_identifier(record)` is true only for that record.

The `|| ordered_records.first` fallback is the interesting part. The `find` returns `nil` whenever the real root isn't in `records` — and that's a routine occurrence here, because the query above it already stripped out posts that are `hidden`, explicitly excluded (`excluded_bluesky_ids`), or fall outside the edition's date `window` (line 26). When the genuine root is gone, the **earliest surviving reply is promoted to root**.

That promotion has a visible downstream consequence: `add_blocks` (line 80) files the block under `block.root.section`, so a promoted reply's section determines where the whole thread lands in the newsletter.

## Step 3 — Build the block

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`Array#-` removes the root from the members. This works on ActiveRecord objects because `ActiveRecord::Core` overrides `hash` and `eql?` to be based on the record's `id` and class — `Array#-` uses a hash set internally, not `==` scanning, so two separately-loaded instances of the same row would still subtract correctly.

## Step 4 — Order the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

Threads are ordered by *their root's* timestamp, not by their latest reply — so a thread started Monday and continued Friday still sits in Monday's slot. `public_send` is needed rather than `&timestamp_method` because the receiver here is `block.root`, not the block itself, so symbol-to-proc doesn't apply.

## Worked example

Given a Bluesky thread A (root) → B → C where B is `hidden`, plus a standalone post D:

1. Query returns `[A, C, D]` ordered by `post_created_at`.
2. `group_by` → `{ "at://A" => [A, C], "at://D" => [D] }`.
3. Group 1: `A.thread_root_uri == A.uri` → root is A, members `[C]`. Group 2: D is its own root, members `[]`.
4. Result: `[DraftBlock(root: A, thread_members: [C]), DraftBlock(root: D, thread_members: [])]`, sorted by A's and D's timestamps.

If A had been excluded instead, group 1 would be `[C]` alone, `find` returns nil, and C becomes root with no members.

`★ Insight ─────────────────────────────────────`
- Thread reconstruction happens in Ruby, not SQL, because the grouping column differs per platform and the root may legitimately be absent from the result set — a SQL self-join would have to model "root missing, promote earliest survivor" as an outer join plus window function. The in-memory version is far more readable at this data volume.
- Note `blocks.sort_by` at the end: Ruby's `sort_by` is not stable, so two blocks whose roots share an identical timestamp have unspecified relative order. Only matters if the platform can emit identical timestamps.
`─────────────────────────────────────────────────`
