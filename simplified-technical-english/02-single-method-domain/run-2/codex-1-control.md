[`build_blocks`](app/services/edition/draft_query.rb:57) converts a flat collection of posts or tweets into chronologically ordered thread blocks.

It takes:

- `records`: Bluesky posts or tweets.
- `timestamp_method`: either `:post_created_at` or `:tweet_created_at`.
- `thread_key`: a method that identifies which thread each record belongs to.

The flow is:

1. **Group records by thread**

   ```ruby
   records.group_by { |record| thread_key.call(record) }
   ```

   Bluesky uses `thread_root_uri`, while Twitter uses `conversation_id`. Standalone records fall back to their own identifier, so they form one-record threads.

2. **Sort each thread chronologically**

   ```ruby
   ordered_records = thread_records.sort_by(&timestamp_method)
   ```

3. **Find the actual thread root**

   It looks for the record whose own identifier—`uri` for Bluesky or `tweet_id` for Twitter—matches the thread’s grouping key.

   If the real root is absent, such as when it falls outside the edition’s date window, it uses the earliest available record instead:

   ```ruby
   root = matching_root || ordered_records.first
   ```

4. **Create a `DraftBlock`**

   Each block contains:

   ```ruby
   DraftBlock.new(
     root: root,
     thread_members: ordered_records - [root]
   )
   ```

   A standalone post therefore produces a block with an empty `thread_members` array.

5. **Sort all blocks by their roots’ timestamps**

   ```ruby
   blocks.sort_by { |block| block.root.public_send(timestamp_method) }
   ```

So conceptually:

```text
flat records
  → group into threads
  → order records inside each thread
  → select each thread’s root
  → build DraftBlock objects
  → order the blocks chronologically
```

The method is deliberately platform-neutral: its callers supply the appropriate timestamp and thread-key logic for Bluesky or Twitter.