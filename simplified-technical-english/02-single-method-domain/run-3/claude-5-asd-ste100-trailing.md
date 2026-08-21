# The build_blocks method

The method is in the file `app/services/edition/draft_query.rb`, on lines 57 to 67.

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

The method changes a flat list of social media records into a list of `DraftBlock` items.

Each `DraftBlock` holds two values:

- `root` — the first record of a thread.
- `thread_members` — the other records of the same thread.

The newsletter editor shows one block for each thread. The block keeps the replies together with the first post.

## The parameters

The method has three parameters:

1. `records` — an array of `Bluesky::Post` records or an array of `Twitter::Tweet` records. The caller reads the records from the database before the call.
2. `timestamp_method` — a symbol with the name of the time attribute. The value is `:post_created_at` for Bluesky. The value is `:tweet_created_at` for Twitter.
3. `thread_key` — a `Method` object. It gives the thread identifier of one record.

The method does not know the platform. The last two parameters supply the platform behavior. Thus the same method operates on Bluesky data and on Twitter data.

## Step 1 — Put the records in groups

`group_by` calls `thread_key` for each record. Records with the same key go into the same group.

`thread_key` is one of two private methods:

- `bluesky_thread_key` gives `thread_root_uri`. If that column is empty, it gives `uri`.
- `twitter_thread_key` gives `conversation_id`. If that column is empty, it gives `tweet_id`.

Each group is thus one thread. A single post with no replies makes a group of one record.

`group_by` gives a hash. `values` keeps the arrays of records and discards the keys.

## Step 2 — Sort each group by time

`sort_by(&timestamp_method)` puts the records of one thread in time order. The oldest record is first.

## Step 3 — Find the root record

The method looks for a record whose thread key is equal to its own identifier. `root_identifier` gives `uri` for a Bluesky post. It gives `tweet_id` for a tweet.

Only the first record of a thread satisfies this test. A reply has a different identifier from the thread key.

If no record satisfies the test, the `||` operator selects `ordered_records.first`. This condition occurs when the true root record is not in the array. The database query can remove the root record for one of these reasons:

- The root record is outside the date window of the edition.
- The root record has the flag `hidden`.
- The editor put the root record in the exclusion list.

The method thus always has a root record. It is the oldest available record of the thread.

## Step 4 — Make the block

`DraftBlock` is a `Data` class. The method makes one block for each thread.

`ordered_records - [root]` removes the root record from the array. The remaining records stay in time order. These records become `thread_members`.

## Step 5 — Sort the blocks

The last line sorts all the blocks. The sort key is the timestamp of the root record.

The method gives back this sorted array.

## Result

The output is an array of `DraftBlock` items in time order. The oldest thread is first.

The caller `add_blocks` then puts each block into a newsletter section. The section comes from the `section` attribute of the root record.

## Example

Six tweets come from the database:

| Tweet | conversation_id | Time |
|---|---|---|
| A | (empty) | 10:00 |
| B | C | 11:05 |
| C | C | 11:00 |
| D | C | 11:10 |
| E | (empty) | 09:00 |
| F | (empty) | 12:00 |

The method makes four groups: `A`, `C` (with B, C, D), `E`, and `F`.

In the group `C`, tweet C is the root record. Its `tweet_id` is equal to its `conversation_id`. The members are B and D, in this order.

The result is four blocks in this sequence: E (09:00), A (10:00), C (11:00), F (12:00).
