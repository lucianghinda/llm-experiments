`build_blocks` converts a flat list of Bluesky posts or Twitter tweets into ordered thread blocks. See [draft_query.rb](<app-root>/app/services/edition/draft_query.rb:57).

It accepts three arguments:

- `records`: The posts or tweets.
- `timestamp_method`: The time field, such as `:post_created_at`.
- `thread_key`: A method that returns the thread identifier.

The method then does these operations:

1. It groups records by their thread identifier.

   - Bluesky uses `thread_root_uri`, or the post URI if no thread root exists.
   - Twitter uses `conversation_id`, or the tweet ID if no conversation exists.

2. It sorts each group by its timestamp.

3. It finds the true thread root. A record is the root when its own identifier equals the thread identifier:

   - Bluesky compares the thread key with `record.uri`.
   - Twitter compares the thread key with `record.tweet_id`.

4. If the true root is not in `records`, it uses the first chronological record as the root. This can occur when the real root is outside the edition date range.

5. It creates a `DraftBlock`:

   ```ruby
   DraftBlock.new(
     root: root,
     thread_members: ordered_records - [root]
   )
   ```

   The remaining records stay in chronological order.

6. Finally, it sorts all blocks by the timestamp of each block’s root.

In short:

```text
flat records
→ group by thread
→ sort each thread
→ select a root
→ put remaining records under that root
→ sort all blocks by root time
```

The tests confirm both normal thread grouping and the missing-root fallback in [draft_query_test.rb](<app-root>/test/services/edition/draft_query_test.rb:34). Section assignment is not part of `build_blocks`; `add_blocks` does that later.