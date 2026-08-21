[`build_blocks`](<app-root>/app/services/edition/draft_query.rb:57) converts social-media records into ordered `DraftBlock` objects.

It does these steps:

1. It groups the records by their thread identifier.
2. It sorts each thread from the earliest record to the latest record.
3. It searches for the root record. A record is the root when its thread identifier is the same as its own identifier.
4. If the root record is not present, it uses the earliest record as the root.
5. It creates one `DraftBlock` for each thread. The block contains:

   - `root`: the selected root record.
   - `thread_members`: all other records, in time order.

6. It sorts all blocks by the time of their root records, from earliest to latest.
7. It returns the sorted blocks.

For Bluesky, the method uses `post_created_at` and the thread-root URI. For Twitter, it uses `tweet_created_at` and the conversation ID. If `records` is empty, it returns an empty array.