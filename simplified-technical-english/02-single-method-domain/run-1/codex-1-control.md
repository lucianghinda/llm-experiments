`build_blocks` converts a flat list of Bluesky posts or tweets into chronologically ordered thread blocks. See [draft_query.rb](app/services/edition/draft_query.rb:57).

It receives:

- `records`: posts or tweets already filtered by date, visibility, exclusions, and organisation.
- `timestamp_method`: either `:post_created_at` or `:tweet_created_at`.
- `thread_key`: a callable method that returns the thread/conversation identifier.

Its process is:

1. Group records by thread.

   - Bluesky uses `thread_root_uri`, falling back to the post’s own `uri`.
   - Twitter uses `conversation_id`, falling back to the tweet’s own `tweet_id`.

2. Sort each thread chronologically using the supplied timestamp method.

3. Identify the real root. A record is the root when its own identifier—`uri` for Bluesky or `tweet_id` for Twitter—matches the group’s thread identifier.

4. If the real root isn’t present, use the earliest available member as the root. This happens, for example, when the actual root is outside the edition’s date window.

5. Create a `DraftBlock`:

   ```ruby
   DraftBlock.new(
     root: root,
     thread_members: ordered_records - [root]
   )
   ```

   The remaining members stay in chronological order.

6. Sort all resulting blocks by their roots’ timestamps.

For example, these Bluesky records:

```text
09:00 root   thread_root_uri = root URI
10:00 reply  thread_root_uri = root URI
```

become:

```ruby
DraftBlock(
  root: root,
  thread_members: [reply]
)
```

Bluesky and Twitter are processed separately, so identifiers cannot accidentally combine records across platforms. Afterwards, `add_blocks` places each block into the newsletter section determined by its root’s section. The thread therefore inherits its root’s categorization. The root/member and missing-root behavior is covered in [draft_query_test.rb](test/services/edition/draft_query_test.rb:31).