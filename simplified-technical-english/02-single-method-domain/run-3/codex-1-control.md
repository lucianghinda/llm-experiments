[`build_blocks`](<app-root>/app/services/edition/draft_query.rb:57) converts a flat collection of posts or tweets into chronologically ordered conversation blocks.

It works in four stages:

1. **Group records by conversation**

   `thread_key` is a callable specific to the platform:

   - Bluesky: `thread_root_uri`, falling back to the post’s own `uri`
   - Twitter: `conversation_id`, falling back to the tweet’s own `tweet_id`

2. **Sort each conversation chronologically**

   `timestamp_method` is either `:post_created_at` or `:tweet_created_at`.

3. **Choose the block’s root**

   It looks for a record whose thread key equals its own platform identifier. That identifies the original post/tweet:

   ```ruby
   thread_key.call(record) == root_identifier(record)
   ```

   If the true root is unavailable—perhaps outside the edition window or excluded—it uses the earliest remaining record as a fallback.

4. **Build and sort the blocks**

   Each group becomes:

   ```ruby
   DraftBlock.new(
     root: root,
     thread_members: ordered_records - [root]
   )
   ```

   The resulting blocks are finally sorted by their roots’ timestamps.

Conceptually:

```text
flat posts/tweets
  → group by conversation
  → order each conversation
  → identify root
  → separate root from replies
  → order conversation blocks chronologically
```

The method is shared by both [`bluesky_blocks`](<app-root>/app/services/edition/draft_query.rb:29) and [`twitter_blocks`](<app-root>/app/services/edition/draft_query.rb:43). It performs no database queries itself; it operates in memory on records already loaded by those callers.