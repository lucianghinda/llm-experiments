`build_blocks` (lines 57–67) turns a flat list of social posts into thread-grouped `DraftBlock`s, sorted chronologically. It's the platform-agnostic core shared by `bluesky_blocks` and `twitter_blocks`.

**Parameters** — all three make it work for either platform:
- `records` — already-filtered, already-ordered posts/tweets
- `timestamp_method` — symbol for the time column (`:post_created_at` vs `:tweet_created_at`)
- `thread_key` — a `Method` object returning the thread identifier (`bluesky_thread_key` → `thread_root_uri || uri`; `twitter_thread_key` → `conversation_id || tweet_id`)

**Step by step:**

1. **Group into threads** (line 58) — `group_by { thread_key.call(record) }.values` buckets records by thread root. Standalone posts form single-element buckets, since their thread key falls back to their own identifier.

2. **Sort within a thread** (line 59) — `sort_by(&timestamp_method)` puts thread members in posting order.

3. **Pick the root** (lines 60–62) — the root is the record whose *thread key* equals its *own identifier* (`root_identifier`: `uri` for Bluesky, `tweet_id` for Twitter). That's the self-referential case, i.e. the post that started the thread. If no such record is in the set — the actual root was excluded, hidden, or falls outside the date window — it falls back to `ordered_records.first`, the earliest surviving reply. So a block always has a root.

4. **Build the block** (line 63) — `DraftBlock` is a `Data.define(:root, :thread_members)` (line 4). `thread_members` is `ordered_records - [root]`, i.e. everything except the root, still in chronological order.

5. **Sort blocks** (line 66) — orders the resulting blocks by their root's timestamp, so the newsletter draft reads chronologically by thread.

The result flows into `add_blocks`, which files each block under the section derived from `block.root.section` — note that only the *root's* section decides placement, so a thread lands in one section regardless of what its replies are tagged with.

One thing worth flagging: `ordered_records - [root]` uses `Array#-`, which relies on `eql?`/`hash`. For ActiveRecord objects that's identity-based on `id` for persisted records, so it's fine here, but it would silently drop duplicates if the same record appeared twice in `records`.
