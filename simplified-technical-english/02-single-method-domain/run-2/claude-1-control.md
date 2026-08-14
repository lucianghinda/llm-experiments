# How `Edition::DraftQuery#build_blocks` works

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

## What it is for

`build_blocks` takes a flat list of social posts and turns it into a list of threads. Each thread becomes a `DraftBlock`, which is a small value object defined at the top of the class:

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A block holds the post that starts a thread (`root`) and every other post in that thread (`thread_members`). A standalone post becomes a block with a root and an empty `thread_members` array. The rest of the class then drops those blocks into newsletter sections.

## The three parameters

The method is written once and used twice, from `bluesky_blocks` and `twitter_blocks`. The two platforms store the same concepts under different names, so the differences are passed in as arguments:

- `records` is an array of already loaded ActiveRecord objects. Both callers end their query chain with `.to_a`, so everything from here on happens in Ruby memory, not in SQL, and the eager loaded associations from `includes` stay attached.
- `timestamp_method` is a symbol naming the timestamp column: `:post_created_at` for Bluesky, `:tweet_created_at` for Twitter.
- `thread_key` is a `Method` object, created with `method(:bluesky_thread_key)` or `method(:twitter_thread_key)`. Passing a bound `Method` rather than a symbol lets the caller hand over a private helper of the same object and call it with `.call`.

Those two helpers answer the question "which thread does this record belong to":

```ruby
def bluesky_thread_key(post)
  post.thread_root_uri.presence || post.uri
end

def twitter_thread_key(tweet)
  tweet.conversation_id.presence || tweet.tweet_id
end
```

If the record points at a thread root, that pointer is the key. If it does not, the record is treated as its own thread root and its own identity becomes the key. This fallback is what makes standalone posts work without a special case.

## Step by step

### 1. Group by thread

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`group_by` builds a hash from thread key to the records carrying that key. Every reply in a thread shares the root's identifier, so replies land in the same bucket as their root. A standalone post lands in a bucket of one, keyed by its own URI or tweet ID. `.values` throws the keys away, leaving an array of arrays: one inner array per thread.

### 2. Order each thread

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

`&timestamp_method` is the symbol to proc conversion, so this is `sort_by(&:post_created_at)` or `sort_by(&:tweet_created_at)` depending on the platform. The thread is now in the order it was written, oldest first. The SQL query already ordered the whole set by the same column, but the grouping does not guarantee the ordering survives in a meaningful way for the caller, so the sort is done explicitly per thread.

### 3. Find the root

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end || ordered_records.first
```

`root_identifier` returns the record's own identity, not its thread pointer:

```ruby
def root_identifier(record)
  case record
  when Bluesky::Post then record.uri
  when Twitter::Tweet then record.tweet_id
  end
end
```

So the test is "does this record's thread key equal its own identity". That is true only for the post that started the thread, because a reply's thread key points at some other record. For a standalone post it is trivially true, since `bluesky_thread_key` fell back to `post.uri` and `root_identifier` also returns `post.uri`.

The `|| ordered_records.first` is the interesting part. The real root may simply not be in `records`. The callers filter by a date window, by `hidden: false`, and by explicit exclusions, so a thread can easily arrive with its first post missing. In that case no record matches, `find` returns `nil`, and the oldest surviving record is promoted to root. The block is never left without one.

### 4. Build the block

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

Array difference removes the root from the ordered list, leaving the remaining posts in chronological order as `thread_members`. `Array#-` compares with `hash` and `eql?`, and ActiveRecord defines both in terms of the record's class and id, so the removal is by identity of the row rather than by object reference. Since all records come from a single query, there are no duplicate rows to worry about.

### 5. Sort the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

Grouping destroys the original ordering across threads, so the finished blocks are sorted again, this time by the timestamp of each block's root. A thread is placed in the draft at the moment it started, not at the moment of its most recent reply. `public_send` is needed because the column name only exists as a symbol at runtime.

## The shape of the result

Input:

```
post A (standalone)
post B (root of a thread)
post C (reply to B)
post D (reply to B)
```

Output:

```
DraftBlock(root: A, thread_members: [])
DraftBlock(root: B, thread_members: [C, D])
```

sorted by the timestamps of A and B.

## Why it matters downstream

`call` starts from an empty hash of newsletter sections and feeds both platforms' blocks through `add_blocks`, which reads `block.root.section` and files the whole block under that section key. Collapsing a thread into a single block with a designated root is what makes that possible: the section of a thread is decided by its first post, and the replies travel with it instead of scattering across sections on their own.
