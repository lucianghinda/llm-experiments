The `build_blocks` method changes a flat list of social-media records into an ordered list of thread blocks.

File: [draft_query.rb](<app-root>/app/services/edition/draft_query.rb:57)

Inputs:

- `records` is an array of posts or tweets.
- `timestamp_method` is `:post_created_at` or `:tweet_created_at`.
- `thread_key` is a method that supplies the thread identifier.

The method does these steps:

1. It groups the records by their thread identifier.
2. It sorts the records in each thread by time. The oldest record comes first.
3. It searches each thread for its root record.
   - For Bluesky, the record URI must equal the thread root URI.
   - For Twitter, the tweet ID must equal the conversation ID.
4. If the root record is not in the input, it uses the oldest record as the root.
5. It creates a `DraftBlock`.
   - `root` contains the selected root record.
   - `thread_members` contains the other records in time order.
6. It sorts all blocks by the time of their root records.

The method returns an array of `DraftBlock` objects. If `records` is empty, it returns an empty array.

For example, assume that one thread contains records `A`, `B`, and `C`. Record `A` is the thread root. The method produces this block:

```ruby
DraftBlock.new(
  root: A,
  thread_members: [B, C]
)
```

The method does not change the input array. It creates new arrays and new `DraftBlock` objects.