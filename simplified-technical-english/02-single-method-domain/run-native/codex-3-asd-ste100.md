The `build_blocks` method makes one draft block for each thread.

It uses three inputs:

- `records` is a list of posts or tweets.
- `timestamp_method` gives the time of each record.
- `thread_key` gives the thread identifier of each record.

The method does these steps:

1. It groups all records by their thread identifier.
2. It sorts the records in each group by time.
3. It searches each group for the thread root.
4. For a Bluesky post, the root identifier is its `uri`.
5. For a tweet, the root identifier is its `tweet_id`.
6. If the method cannot find the root, it uses the first record in the time order.
7. It makes a `DraftBlock` with the root and the other records.
8. It sorts all draft blocks by the time of their roots.

The result is a time-ordered list of draft blocks. Each block contains one thread root and its thread members.
