**Note on tooling:** No MCP tool fits this; falling back to `Read` because you asked me specifically to read this file, and the `rails_*` MCP tools aren't connected in this session.

`★ Insight ─────────────────────────────────────`
- `build_blocks` is a **shared algorithm with injected strategies**: the two callers (`bluesky_blocks`, `twitter_blocks`) pass in *what to sort by* (a Symbol) and *how to compute thread identity* (a `Method` object). One implementation, two platforms with different column names.
- `DraftBlock = Data.define(:root, :thread_members)` (line 4) is Ruby 3.2+ `Data` — an immutable value object. It's the contract this query hands to the view layer: every thread collapses to "one root + its replies."
`─────────────────────────────────────────────────`

## What it does

```ruby
def build_blocks(records, timestamp_method, thread_key)
```

It takes a **flat list** of social posts and turns it into a **chronologically ordered list of threads**, where each thread knows which post is its root.

### The parameters

| Param | Bluesky call (line 40) | Twitter call (line 54) |
|---|---|---|
| `records` | `Bluesky::Post` array | `Twitter::Tweet` array |
| `timestamp_method` | `:post_created_at` | `:tweet_created_at` |
| `thread_key` | `method(:bluesky_thread_key)` | `method(:twitter_thread_key)` |

`method(:bluesky_thread_key)` grabs the private method (line 87) as a first-class callable object, so `build_blocks` can invoke it with `.call(record)` without knowing anything about Bluesky.

### Step 1 — Group into threads (line 58)

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

The thread key is *"the root's identifier, or my own if I am the root"*:

```ruby
def bluesky_thread_key(post) = post.thread_root_uri.presence || post.uri
def twitter_thread_key(tweet) = tweet.conversation_id.presence || tweet.tweet_id
```

So a standalone post keys on itself, and every reply in a thread keys on the shared root. `group_by(...).values` discards the keys and leaves an array of arrays — one inner array per thread.

### Step 2 — Order within the thread (line 59)

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

`&:post_created_at` is `Symbol#to_proc` — it calls that method on each record. This is why the timestamp is passed as a Symbol rather than a lambda: it plugs straight into `sort_by` and later into `public_send`.

### Step 3 — Find the root (lines 60–62)

```ruby
root = ordered_records.find { |record|
  thread_key.call(record) == root_identifier(record)
} || ordered_records.first
```

This is the clever bit. `root_identifier` (line 69) returns the record's **own** identity (`uri` for Bluesky, `tweet_id` for Twitter). A record is the root exactly when *its thread key equals its own identity* — i.e. `thread_root_uri` is blank or points at itself.

The `|| ordered_records.first` fallback matters a lot here. The real root may be missing from `records` because it was hidden, explicitly excluded (lines 32/46), or falls outside the edition's date `window` (line 26). Rather than producing a rootless block, the earliest surviving reply gets promoted to root.

### Step 4 — Build the value object (line 63)

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`Array#-` removes the root by equality. ActiveRecord defines `==`/`hash` on the primary key, so this correctly drops the root even though `root` and the array element may be different object instances. What remains is the replies, still in chronological order.

### Step 5 — Order the threads (line 66)

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

`public_send` is the counterpart to the `&:symbol` trick from step 2 — same Symbol, now used for a dynamic method call on a single object. Threads are ordered by when the root was posted, giving the newsletter draft a stable chronological spine.

### Where the output goes

`call` (line 10) feeds these blocks into `add_blocks` (line 78), which routes each block into a newsletter section based on `block.root.section` — so the root's classification decides where the whole thread lands.

`★ Insight ─────────────────────────────────────`
- Note the deliberate two-layer exclusion in the callers: `excluded_*_ids` drops individually excluded posts, while `excluded_*_thread_roots` (lines 111–115) drops *entire threads* — but only when the excluded record is itself a genuine root (`thread_root_uri == uri`). Excluding a reply doesn't nuke its siblings.
- Passing a `Method` object instead of subclassing keeps this a single flat class. The trade-off: the platform knowledge is now split between `thread_key` (how threads group) and `root_identifier`'s `case` statement (what identity means) — those two must stay in sync, or `find` silently returns `nil` and every thread falls back to `first`.
`─────────────────────────────────────────────────`
