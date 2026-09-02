`build_blocks` (app/services/edition/draft_query.rb:57) is the platform-agnostic core of this query. Both `bluesky_blocks` (:40) and `twitter_blocks` (:54) hand it an already-filtered, already-ordered array of records plus two pieces of platform knowledge, and get back a chronological list of `DraftBlock` values.

**The three parameters**

- `records` — plain array of `Bluesky::Post`s or `Twitter::Tweet`s, already scoped to the edition's date window, non-hidden, and with exclusions removed.
- `timestamp_method` — a symbol (`:post_created_at` or `:tweet_created_at`). Used twice: with `sort_by(&timestamp_method)` via `Symbol#to_proc`, and with `public_send` on line 66.
- `thread_key` — a `Method` object (`method(:bluesky_thread_key)` / `method(:twitter_thread_key)`), so the method can be `.call`ed uniformly regardless of platform.

**What it does**

1. **Group into threads** (:58). `records.group_by { thread_key.call(record) }` collapses a conversation into one group. For Bluesky the key is `thread_root_uri.presence || uri` (:88); for Twitter it's `conversation_id.presence || tweet_id` (:92). The `presence ||` fallback means a standalone post — no thread root recorded — keys on its own identifier and lands in a group of one. `.values` discards the keys, leaving arrays of records per thread.

2. **Order each thread** (:59). Chronological by the platform's timestamp column.

3. **Pick the root** (:60–62). It looks for the record whose *thread key* equals its *own* identifier — `root_identifier` returns `uri` for Bluesky, `tweet_id` for Twitter (:69–76). That's precisely the "this post is its own thread root" test. The `|| ordered_records.first` fallback matters: the real root may not be in `records` at all — it could fall outside the edition window, be `hidden`, or be individually excluded — in which case the earliest surviving reply stands in as the root so the thread still renders.

4. **Wrap it** (:63). `DraftBlock` is a `Data.define(:root, :thread_members)` (:4). `ordered_records - [root]` leaves the remaining thread members in chronological order. (Array difference works here because ActiveRecord defines `==`/`hash` on the primary key.)

5. **Sort blocks** (:66). Finally the whole set of blocks is sorted by the *root's* timestamp, so a thread is positioned by when it started, not by its most recent reply. `add_blocks` (:78) then files each block under its root's newsletter section — meaning the root post's `section` determines placement for the entire thread.

**Worth noting**

- Root exclusions are handled upstream, not here: `without_bluesky_root_exclusions` (:95) / `without_twitter_root_exclusions` (:101) drop *every* record sharing an excluded root's thread id, so excluding a thread root removes the whole thread rather than promoting a reply via the step-3 fallback. Excluding a non-root only removes that one record.
- `root_identifier` returns `nil` for any class other than `Bluesky::Post` / `Twitter::Tweet` (the `case` has no `else`), so a third platform would silently never match the root test and always fall through to `ordered_records.first`.
- `sort_by` isn't stable in Ruby, so two blocks whose roots share an identical timestamp have unspecified relative order.
