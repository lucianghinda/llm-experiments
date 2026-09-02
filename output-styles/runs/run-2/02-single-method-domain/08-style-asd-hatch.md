[MCP VIOLATION] — `rails_search_code(pattern:"build_blocks", match_type:"trace")` was the correct tool here; I used `Read` on a file I am not editing because you asked for a direct read of it.

## What `build_blocks` does

`app/services/edition/draft_query.rb:57` groups flat social-media records into thread blocks for a newsletter draft. It is shared code: Bluesky and Twitter both call it (`:40`, `:54`) with different parameters.

**Parameters**

- `records` — the posts or tweets already loaded for the edition window.
- `timestamp_method` — a symbol: `:post_created_at` or `:tweet_created_at`.
- `thread_key` — a `Method` object (`bluesky_thread_key` / `twitter_thread_key`) that gives the thread identity of one record.

**Steps**

1. **Group** (`:58`). `group_by` puts each record into a bucket by its thread key. The key is the thread root (`thread_root_uri` / `conversation_id`), or the record's own id if the field is empty (`:87`–`:93`). Therefore a single post makes a bucket of one.
2. **Sort inside the thread** (`:59`). The members go in time order, oldest first.
3. **Find the root** (`:60`–`:62`). The root is the record whose thread key is equal to its own identifier — `uri` for Bluesky, `tweet_id` for Twitter (`root_identifier`, `:69`). This is the record that starts the thread. If no such record is in the set, the code uses the oldest record instead (`|| ordered_records.first`). This happens when the true root is hidden, excluded, or outside the date window.
4. **Make the block** (`:63`). `DraftBlock` is a `Data` object with `root` and `thread_members`. `ordered_records - [root]` removes the root and keeps the other members in time order. Array subtraction is correct here, because Active Record compares records by id.
5. **Sort the blocks** (`:66`). All blocks go in time order by the timestamp of their root.

**Example.** Three tweets with the same `conversation_id`, plus one independent tweet, become two blocks: one block with the parent tweet as `root` and two replies in `thread_members`, and one block with the independent tweet as `root` and an empty `thread_members`.

The result then goes to `add_blocks` (`:78`), which puts each block into a newsletter section, based on `block.root.section`. The section of the root — not of the replies — decides the position.
