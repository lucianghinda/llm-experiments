[`build_blocks`](app/services/edition/draft_query.rb:57) converts a flat list of posts or tweets into a chronological list of conversation blocks.

It works like this:

1. **Groups records into threads.**  
   `thread_key` returns the thread identifier—Bluesky’s root URI or Twitter’s conversation ID.

2. **Sorts each thread by time.**  
   `timestamp_method` is either `post_created_at` or `tweet_created_at`.

3. **Finds the thread’s root record.**  
   A record is the root when its thread identifier matches its own identifier:
   - Bluesky: `uri`
   - Twitter: `tweet_id`

   If the real root is absent—perhaps outside the edition’s date range—the earliest available record becomes the root.

4. **Creates a `DraftBlock`.**  
   Each block contains:
   - `root`: the root or earliest available record
   - `thread_members`: all remaining records, in chronological order

5. **Sorts all blocks by their root’s timestamp.**

In short:

```text
flat records
→ group by conversation
→ order each conversation
→ choose its root
→ separate root from replies
→ order all conversations by time
```

The method is generic so the same logic can handle both Bluesky posts and Twitter tweets.