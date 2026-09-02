## `build_blocks` (app/services/edition/draft_query.rb:57)

The method changes a flat list of social posts into a list of thread blocks. Each block has one root post and its related replies.

### Parameters

- `records` — the posts or tweets from the database, in time sequence.
- `timestamp_method` — a symbol, `:post_created_at` for Bluesky or `:tweet_created_at` for Twitter.
- `thread_key` — a `Method` object (`method(:bluesky_thread_key)` or `method(:twitter_thread_key)`). It gives the identifier of the thread of a record.

### Steps

1. **Group into threads** (line 58). The method calls `thread_key` on each record and groups the records by the result. For Bluesky, the key is `thread_root_uri` or, if that value is empty, the `uri` of the post (line 88). For Twitter, the key is `conversation_id` or the `tweet_id` (line 92). Thus all posts of one thread get the same key. `.values` keeps only the groups, and removes the keys.

2. **Sort each thread** (line 59). The method puts the records of one thread in sequence by their timestamp. The oldest record is first.

3. **Find the root** (lines 60–62). The method looks for the record whose thread key is equal to its own identifier (`uri` for Bluesky, `tweet_id` for Twitter — line 69). This condition is true only for the first post of the thread, because a reply has the key of a different record. If no record agrees with the condition, the method uses the oldest record as the root (`|| ordered_records.first`). This fallback is necessary when the root post is not in the time window, or when a person hid or excluded it.

4. **Make the block** (line 63). The method makes a `DraftBlock` (a `Data` object — line 4) with the root and, as `thread_members`, all other records of the thread in time sequence.

5. **Sort the blocks** (line 66). At the end, the method sorts all blocks by the timestamp of their root. Thus the newsletter shows the threads in the sequence of their start.

### Result

An array of `DraftBlock` values. `call` sends this array to `add_blocks` (line 78), which puts each block in a newsletter section. The section comes from the `section` attribute of the root record.
