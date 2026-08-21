# `Edition::DraftQuery#build_blocks`

```ruby
def build_blocks(records, timestamp_method, thread_key)
  blocks = records.group_by { |record| thread_key.call(record) }.values.map do |thread_records|
    ordered_records = thread_records.sort_by(&timestamp_method)
    root = ordered_records.find do |record|
      thread_key.call(record) == root_identifier(record)
    end || ordered_records.first
    DraftBlock.new(root: root, thread_members: ordered_records - [root])
  end

  blocks.sort_by { |block| block.root.public_send(timestamp_method) }
end
```

## What it does

It takes a flat list of social posts and turns it into a list of `DraftBlock`
values, one per conversation thread. Each block has one `root` post and the
rest of the thread in `thread_members`. The blocks come back sorted oldest
first.

It is the shared step for both platforms. `bluesky_blocks` and
`twitter_blocks` each run their own database query, then hand the rows to this
one method. That is why the platform-specific parts are passed in as
arguments instead of being written inside.

## The three arguments

| Argument | What it is | Bluesky | Twitter |
|---|---|---|---|
| `records` | Array of already loaded rows, filtered and ordered by the DB | `Bluesky::Post` rows | `Twitter::Tweet` rows |
| `timestamp_method` | A Symbol naming the timestamp column | `:post_created_at` | `:tweet_created_at` |
| `thread_key` | A `Method` object that returns the thread identity of a row | `method(:bluesky_thread_key)` | `method(:twitter_thread_key)` |

Note the two callables are different kinds. `timestamp_method` is a plain
Symbol, so it is used with `&` (`sort_by(&timestamp_method)`) and with
`public_send`. `thread_key` is a bound `Method`, so it is used with `.call`.

The two thread-key functions are:

```ruby
def bluesky_thread_key(post)  = post.thread_root_uri.presence || post.uri
def twitter_thread_key(tweet) = tweet.conversation_id.presence || tweet.tweet_id
```

Both answer the same question: *which thread does this row belong to?* If the
row carries a thread pointer, that pointer is the answer. If it does not, the
row is its own thread of one, so the row's own identifier is the answer.

## Step by step

### 1. Group by thread

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`group_by` builds a Hash of `thread key => [rows]`. `.values` throws the keys
away and keeps only the arrays. After this line the method works with a list
of thread groups. A standalone post ends up in a group of one, because its
key is its own identifier and no other row shares it.

### 2. Order each thread

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

Oldest first, so a thread reads top to bottom in the newsletter. The DB query
already ordered the whole result set, but this sort makes the block correct on
its own, independent of the caller.

### 3. Pick the root

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end || ordered_records.first
```

`root_identifier` returns the row's own identity, chosen by class:

```ruby
def root_identifier(record)
  case record
  when Bluesky::Post  then record.uri
  when Twitter::Tweet then record.tweet_id
  end
end
```

So the test "thread key equals own identifier" means "this row is the head of
its own thread". It is true in two cases:

- The row is the real thread root: its `thread_root_uri` / `conversation_id`
  points at itself. (Same test the models expose as `thread_root?`.)
- The row has no thread pointer at all: the key falls back to its own `uri` /
  `tweet_id`, so the two sides match trivially. A standalone post is the root
  of its own one-post block.

The `|| ordered_records.first` is the fallback for the case where the real
root is not in `records`. That happens often here, because the caller filters
by date window, by `hidden: false`, and by the edition's exclusions. If the
root reply was posted before the window or was hidden, the group still holds
its replies, and the earliest surviving reply is promoted to root so the
thread is not lost.

### 4. Build the value object

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is `Data.define(:root, :thread_members)` — an immutable struct.
`ordered_records - [root]` is Array difference, which relies on `==` and
`hash`. ActiveRecord defines `==` as "same class and same id", so the root row
is removed and the remaining replies stay in chronological order. Consumers
put the thread back together as `[block.root] + block.thread_members`
(see `Newsletter::BlockMarkdown` and `shared/_draft_block.html.erb`).

### 5. Sort the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

Threads are ordered by the timestamp of their root, not by their newest reply.
A thread therefore appears in the newsletter at the point where it started.
`public_send` is needed because `timestamp_method` is a Symbol, not a Method.

## Where the result goes

`call` starts from an empty Hash of newsletter sections and pushes each block
into a section with `add_blocks`:

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
```

The section is read from the **root** only. The whole thread follows its root's
section, and the `section` value on the replies is ignored. A block whose
section is not one of the ordered top-level sections is silently dropped.

## Things worth knowing

- **Bluesky and Twitter blocks stay separate.** `call` runs `add_blocks` twice,
  so within one section the Bluesky blocks come first as a sorted run, then the
  Twitter blocks as a second sorted run. There is no merge across platforms.
- **Grouping happens in Ruby, not SQL.** Both callers end their scope with
  `.to_a`, so the whole window is loaded, then grouped in memory. Fine for one
  edition's worth of posts; it would not be for a large window.
- **The root-vs-first distinction matters.** With a real root present the block
  is a true thread. With the fallback it is a partial thread presented as if
  the first surviving reply were the start.
- **Exclusions are handled before this method.** Individual posts are removed
  by id; whole threads are removed by matching `thread_root_uri` /
  `conversation_id` against roots the editor excluded. `build_blocks` only ever
  sees rows that survived.
