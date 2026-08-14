# The method `build_blocks`

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

The method is in `app/services/edition/draft_query.rb`, in the class `Edition::DraftQuery`.

## The job of the method

The method receives a flat list of records. It returns a list of blocks.

A record is one Bluesky post or one tweet. A block is one thread. A thread is a group of
records. One record starts the thread. The other records answer that record.

The database gives the records in one flat list. The newsletter needs threads, not single
records. This method makes the threads.

## The three parameters

The method has three parameters. Each parameter hides one difference between the two
platforms.

**`records`** is an array of model objects. The array holds Bluesky posts, or the array
holds tweets. The array never holds both types together.

**`timestamp_method`** is a symbol. The symbol is the name of the method that gives the time
of a record. For Bluesky the symbol is `:post_created_at`. For Twitter the symbol is
`:tweet_created_at`.

**`thread_key`** is a `Method` object. The caller builds the object with
`method(:bluesky_thread_key)` or with `method(:twitter_thread_key)`. The object answers one
question: which thread does this record belong to?

Two callers use the method. `bluesky_blocks` calls it, and `twitter_blocks` calls it. The
two callers pass different parameters. The body of `build_blocks` stays the same. So one
piece of code serves both platforms.

## Step 1: put the records into groups

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`group_by` calls `thread_key` one time for each record. Records with the same key go into
the same group.

For Bluesky the key comes from `bluesky_thread_key`:

```ruby
post.thread_root_uri.presence || post.uri
```

For Twitter the key comes from `twitter_thread_key`:

```ruby
tweet.conversation_id.presence || tweet.tweet_id
```

The rule is the same on both platforms. If the record knows its thread, the method uses the
identifier of the thread. If the record does not know its thread, the method uses the
identifier of the record itself.

`.values` removes the keys. Only the groups stay. The code does not need the keys again.

A record that is not part of a thread also makes a group. That group holds one record.

## Step 2: sort each group by time

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

The records inside one group go into time order. The oldest record comes first.

The `&` operator changes the symbol into a block. So `&:post_created_at` calls
`post_created_at` on each record.

## Step 3: find the root of the group

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end
```

The root is the record that starts the thread. The test compares two values for each record:

1. the thread key of the record
2. the value from `root_identifier`

`root_identifier` is a small method in the same class. It returns `uri` for a Bluesky post.
It returns `tweet_id` for a tweet. It returns the identifier of the record itself.

When the two values are equal, the record points at itself. Such a record starts the thread.
The models agree with this test. `Bluesky::Post#thread_root?` and `Twitter::Tweet#thread_root?`
make the same comparison.

A record without a thread also passes the test. Its key falls back to its own identifier. So
a single record is the root of its own block.

`find` stops at the first record that passes. The group is already in time order. So the
oldest match wins if more than one record passes.

## Step 4: use the oldest record when no root is present

```ruby
end || ordered_records.first
```

`find` returns `nil` when no record passes the test. `nil` is false in Ruby. So the `||`
operator selects `ordered_records.first`. That is the oldest record in the group.

This case is normal. It is not an error. The query that builds `records` removes hidden
records. It removes records that the editor excluded. It also keeps only the records inside
the dates of the edition. The true root can disappear for any of those reasons. The answers
stay, and they still share one thread key. The block then starts with the oldest record that
remains.

## Step 5: build one block

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a small value object. Line 4 of the file defines it:

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A `Data` object is frozen. Nothing can change the block after the method builds it.

`ordered_records - [root]` removes the root from the list. The other records become the
thread members. Array subtraction keeps the order of the left array. So the thread members
stay in time order.

Array subtraction removes every element that is equal to the root. Two Active Record objects
are equal when they have the same class and the same identifier. In practice each record
appears one time, so the code removes one record.

## Step 6: sort the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

The last line puts the blocks in time order. The time of the root decides the position of
the block.

The code uses `public_send` because the name of the method is in a variable. The result is
the same as the `&` operator in step 2.

The whole thread moves as one unit. A late answer inside a thread does not move the block to
the end of the list.

## What happens after the method returns

The public method `call` uses the result:

```ruby
empty_sections.tap do |sections|
  add_blocks(sections, bluesky_blocks)
  add_blocks(sections, twitter_blocks)
end
```

`add_blocks` reads `block.root.section` and puts the block into that section of the
newsletter. Only the root decides the section. The section of an answer has no effect.

`build_blocks` runs two times, one time for each platform. The two results stay separate.
The Bluesky blocks enter the sections first. The Twitter blocks enter after them. So the
blocks inside one section are not in one continuous time order across the two platforms.

## Points to remember

- The method does not touch the database. The two callers add `to_a` before they call it.
  All the grouping and sorting happens in Ruby memory.
- The method does not change the input array. It returns a new array of frozen objects.
- Every block has a root. The `||` makes sure of that. So `add_blocks` can call
  `block.root.section` without a check for `nil`.
- A block can have zero thread members. That happens for a single record, and it happens
  when only the root of a thread survives the filters.
- `sort_by` in Ruby is not stable. Two roots with the same timestamp can appear in any
  order.
- The method knows nothing about Bluesky and nothing about Twitter. It knows only the three
  parameters. To add a third platform, you write a new key method and pass a new timestamp
  name. You do not change `build_blocks`.
