# `build_blocks` in `Edition::DraftQuery`

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

## Purpose

The method changes a flat list of social posts into a list of `DraftBlock` values.
Each block holds one root post and the replies to that post.
The blocks are in time order, oldest first.

Two callers use the method: `bluesky_blocks` and `twitter_blocks`.
Each caller reads its records from the database first.
This method does all of the group work in memory.

## The three parameters

The parameters hold all of the platform differences.
Thus one method serves both Bluesky and Twitter.

| Parameter | Type | Bluesky value | Twitter value |
|---|---|---|---|
| `records` | Array of models | `Bluesky::Post` records | `Twitter::Tweet` records |
| `timestamp_method` | Symbol | `:post_created_at` | `:tweet_created_at` |
| `thread_key` | `Method` object | `method(:bluesky_thread_key)` | `method(:twitter_thread_key)` |

## Step 1 - group the records into threads

`group_by` collects the records that have the same thread key.

- Bluesky key: `post.thread_root_uri.presence || post.uri`
- Twitter key: `tweet.conversation_id.presence || tweet.tweet_id`

All of the records in one thread have the same key.
Thus one group is one thread.

A record that is not in a thread makes a group of one record.
Its key is its own identifier, and no other record has that key.

`.values` removes the keys. Only the groups of records stay.

## Step 2 - sort each group

`sort_by(&timestamp_method)` puts the oldest record of the group first.
The `&` operator changes the Symbol into a block. This is `Symbol#to_proc`.

## Step 3 - find the root of the thread

`root_identifier` gives the identifier of the record: `uri` for Bluesky, `tweet_id` for Twitter.

A record is the root when its thread key is equal to its own identifier.
This is the same test as `thread_root?` in the two models.

`find` reads the group in time order. Thus the earliest root wins.

## Step 4 - the fallback

```ruby
end || ordered_records.first
```

The true root is not always in the group.
The root can be outside the date window of the edition, or the root can have `hidden: true`.
In this condition the method makes the oldest record of the group the root.

A block always has a root. The method never returns `nil` for `root`.

An excluded root is a different condition.
`without_bluesky_root_exclusions` and `without_twitter_root_exclusions` remove the full thread from the query.
Thus the fallback does not apply to an excluded root.

## Step 5 - build the block

`DraftBlock = Data.define(:root, :thread_members)` is an immutable Ruby `Data` value.

`ordered_records - [root]` removes the root from the group.
The other records stay in time order and become `thread_members`.

Array subtraction compares with `eql?` and `hash`.
Active Record makes two instances equal when the class and the `id` are equal.

## Step 6 - sort the blocks

`public_send(timestamp_method)` reads the timestamp from the root record.
`public_send` is necessary, because the name of the method is in a variable.

The method returns the blocks in time order.

## What the caller does with the result

`add_blocks` reads `block.root.section` and puts the block in the correct newsletter section.
Thus the root controls the section of the full thread. The replies do not change it.

## Notes on the design

- The method calls the supplied methods in three different ways: `&` for the Symbol block, `.call` for the `Method` object, and `public_send` for the Symbol name. Each way is correct in its position, but the style is not consistent.
- The name `timestamp_method` holds a Symbol, not a `Method`. The name `thread_key` holds a `Method`, not a key. The two names can confuse a reader.
- The database only filters and sorts. Ruby does the group work. The number of records for one edition is small, thus the cost is low.
- `thread_key.call` runs one time in `group_by`, and again for each record in `find`.
- The records are already in time order from the `order` clause of the query. The sort in step 2 is thus a safety step.
