# How `build_blocks` works

`build_blocks` lives in `Edition::DraftQuery` and does one job: it takes a flat list of social media records and turns it into an ordered list of threads, where each thread knows which record starts it and which records follow it.

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

## The three parameters

The method is written once and used twice, so all the platform-specific knowledge is passed in as arguments rather than baked into the body.

`records` is an already loaded array of model instances. The two callers hand it different things: `bluesky_blocks` passes `Bluesky::Post` records, `twitter_blocks` passes `Twitter::Tweet` records. Both callers have already filtered by date window, dropped hidden records, removed excluded ids, eager loaded associations, and called `to_a`, so `build_blocks` never touches the database.

`timestamp_method` is a symbol naming the attribute that holds the publish time. It is `:post_created_at` for Bluesky and `:tweet_created_at` for Twitter. The method uses it in two different ways, which is worth noticing: as a symbol passed to `sort_by(&timestamp_method)` and as an argument to `public_send(timestamp_method)`. Both reach the same attribute.

`thread_key` is a `Method` object built with `method(:bluesky_thread_key)` or `method(:twitter_thread_key)`. Because it is a `Method` and not a symbol, the code calls it with `thread_key.call(record)`. Each implementation returns the identifier of the thread a record belongs to:

```ruby
def bluesky_thread_key(post)
  post.thread_root_uri.presence || post.uri
end

def twitter_thread_key(tweet)
  tweet.conversation_id.presence || tweet.tweet_id
end
```

A record that is a reply carries the identifier of the thread it replies into. A record that is not part of any thread falls back to its own identifier, so it becomes a thread of one.

## Step 1: group records into threads

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`group_by` builds a hash from thread identifier to the array of records sharing that identifier. Calling `.values` throws the keys away and leaves an array of arrays, one inner array per thread. Standalone posts end up in single element arrays.

## Step 2: sort each thread chronologically

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

Inside a thread, the records are put in publish order. The `&` converts the symbol into a block, so this is equivalent to `sort_by { |record| record.post_created_at }` for Bluesky. This ordering matters for two reasons: it fixes the reading order of the thread, and it provides the fallback root in the next step.

## Step 3: find the root of the thread

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end || ordered_records.first
```

This is the interesting part. The root of a thread is the record whose thread key equals its own identifier. `root_identifier` returns the record's own id, per platform:

```ruby
def root_identifier(record)
  case record
  when Bluesky::Post
    record.uri
  when Twitter::Tweet
    record.tweet_id
  end
end
```

So for a Bluesky post, the test is `thread_root_uri (or uri) == uri`. That is true only for the post that opens the thread, because a reply points at somebody else's uri. For a standalone post the test is also true, because `bluesky_thread_key` already fell back to `post.uri`.

The `|| ordered_records.first` is the safety net. The date window in `window` can slice a thread in half. If the opening post was published before `edition.start_date`, it is not in `records` at all, and `find` returns `nil`. In that case the method treats the earliest record it does have as the root. This means a block always has a root, never `nil`, even when the real conversation starter is missing from the query.

## Step 4: wrap the thread in a value object

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is declared at the top of the class as `Data.define(:root, :thread_members)`, so it is an immutable value object with two readers. The root is stored separately, and `thread_members` holds everything else in the thread, still in chronological order, because array subtraction preserves the order of the receiver. `- [root]` uses equality, and since these are Active Record instances of the same class with the same id, only the root record is removed.

Note that `thread_members` is the tail of the thread, not the whole thread. A standalone post produces a `DraftBlock` with a root and an empty `thread_members` array.

## Step 5: sort the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

The blocks come out of `group_by` in the order the thread identifiers were first encountered, which is close to but not guaranteed to be the order the caller wants. This final sort puts the threads in chronological order by the time of their root record. A thread is therefore positioned by when it started, not by when it last received a reply.

`public_send` is used here instead of `&timestamp_method` because the receiver is `block.root` rather than the block itself, so the symbol cannot be turned into a to_proc shorthand.

## What the caller does with the result

`build_blocks` returns a plain array of `DraftBlock` values. `bluesky_blocks` and `twitter_blocks` each return their own array, and `call` merges both into the section hash:

```ruby
def call
  empty_sections.tap do |sections|
    add_blocks(sections, bluesky_blocks)
    add_blocks(sections, twitter_blocks)
  end
end
```

`add_blocks` reads `block.root.section`, maps it through `Newsletter::SectionTaxonomy`, and appends the block to the matching section, skipping any section key the taxonomy does not recognise. This is why the root matters beyond ordering: the root record decides which newsletter section the whole thread lands in, and the replies have no say.

## Why it is written this way

Three design choices stand out.

Sorting happens twice, at two levels. Once inside each thread so replies read in order, and once across threads so the newsletter reads in order. Neither sort can substitute for the other.

Platform differences are pushed to the boundary. Bluesky and Twitter name their fields differently, but the only thing `build_blocks` needs to know is "how do I get a timestamp" and "how do I get a thread key". Both are injected. The one place platform knowledge leaks back in is `root_identifier`, which does a `case` on the record class instead of taking a third injected callable. That is a small inconsistency in an otherwise cleanly parameterised method.

The method assumes nothing about completeness. Because editions are date bounded, threads arrive truncated, and the `||` fallback keeps the output well formed instead of raising or producing a block with a nil root.
