`build_blocks` (`app/services/edition/draft_query.rb:57`) turns a flat list of posts/tweets into thread-grouped `DraftBlock`s, sorted chronologically.

It's platform-agnostic — both `bluesky_blocks` and `twitter_blocks` call it, passing the timestamp attribute name and a `Method` object that extracts the thread key.

**Step by step:**

1. **Group into threads** (line 58) — `group_by { thread_key.call(record) }` buckets records by thread. For Bluesky the key is `thread_root_uri.presence || uri`; for Twitter it's `conversation_id.presence || tweet_id`. So a standalone post keys on its own identifier and ends up alone in its bucket; replies in a thread all share the root's identifier. `.values` discards the keys, leaving arrays of records.

2. **Order within the thread** (line 59) — `sort_by(&timestamp_method)` sorts by `post_created_at` / `tweet_created_at`, giving the thread's natural reading order.

3. **Pick the root** (lines 60–62) — finds the record whose *thread key* equals its *own* identifier (`root_identifier`: `uri` for Bluesky, `tweet_id` for Twitter). That's the self-referential record, i.e. the thread's first post. The `|| ordered_records.first` fallback matters when the actual root isn't in the result set — filtered out by the date window, `hidden: true`, or an exclusion — in which case the earliest surviving record is promoted to root.

4. **Build the block** (line 63) — `DraftBlock` (a `Data` type, line 4) holds `root` plus `thread_members: ordered_records - [root]`, the remaining replies in chronological order.

5. **Sort the blocks** (line 66) — orders threads by their root's timestamp via `public_send(timestamp_method)`.

Downstream, `add_blocks` reads `block.root.section` to file each block into a newsletter section, so the root choice determines both the section and the block's position in the edition.

One thing worth noting: `ordered_records - [root]` uses `Array#-`, which relies on `hash`/`eql?`. ActiveRecord defines these on `id`, so it removes exactly the root for persisted records — but a bucket of unsaved records would have `id: nil` and all compare equal, dropping everything. Not a concern here since these come from `to_a` on a DB query.
