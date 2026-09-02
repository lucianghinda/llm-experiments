No MCP tool fits this; falling back to `Read` because you named the file directly and no `rails_*` MCP tools are connected in this session.

## What the class does

`Edition::DraftQuery` (`app/services/edition/draft_query.rb`) collects the social posts for one newsletter edition. It groups the posts into threads. Then it sorts the threads into newsletter sections.

`call` returns a Hash:
- Each key is a top-level section key from `Newsletter::SectionTaxonomy`.
- Each value is an array of `DraftBlock`.

`DraftBlock` is a `Data` class with two fields: `root` (the first post of a thread) and `thread_members` (the other posts of the same thread).

## The steps

**1. Make the empty result (`empty_sections`, line 21)**

`Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }` makes one key for each top-level section. Every key gets its own empty array. The taxonomy sets the order of the keys.

**2. Set the time window (`window`, line 25)**

The window starts at the start of `edition.start_date`. It ends at the start of the day after `edition.end_date`. The range operator is `...`, so the end is exclusive. The result includes the full last day.

**3. Read the Bluesky posts and the tweets (lines 29–55)**

The two methods do the same work on two different models. Each query:
- Reads from the organisation of the edition (`bluesky_posts` or `tweets`).
- Keeps only records in the window that are not `hidden`.
- Removes the records that the edition excludes (see step 6).
- Preloads `url_titles`, the author and the author platform accounts, and the snapshot image. This prevents N+1 queries in the view.
- Orders the records by the creation time.

**4. Group the records into threads (`build_blocks`, line 57)**

The method groups the records by a thread key:
- For Bluesky, the key is `thread_root_uri`, or `uri` if `thread_root_uri` is empty (line 87).
- For Twitter, the key is `conversation_id`, or `tweet_id` if `conversation_id` is empty (line 91).

In each group, the method sorts the records by time. Then it looks for the record whose own identifier is equal to the thread key. That record is the true root of the thread. If no such record is present — for example, when the root post is outside the time window — the method uses the earliest record as the root. The other records become `thread_members`.

Last, the method sorts all blocks by the time of the root.

**5. Put the blocks into sections (`add_blocks`, line 78)**

For each block, the method asks `Newsletter::SectionTaxonomy.for(block.root.section)` for the section key. If the key is not a top-level key of the result Hash, the method ignores that block. If the key is present, the method appends the block.

**6. Apply the exclusions (lines 95–129)**

`edition.edition_exclusions` is a polymorphic association. `excluded_records` loads the excluded records for one model class.

The class removes records at two levels:
- **Single record:** `excluded_bluesky_ids` / `excluded_twitter_ids` remove that one post or tweet.
- **Full thread:** if an excluded record is itself a thread root (its `thread_root_uri` is equal to its `uri`, or its `conversation_id` is equal to its `tweet_id`), then the class removes every record of that thread.

The `without_*_root_exclusions` methods return the scope without a change when the exclusion list is empty. This is necessary, because `where.not(column: [])` matches no rows in SQL and would empty the result.

## Two behaviours to keep in mind

- **Order in a section is per platform, not per time.** `call` adds all Bluesky blocks first, then all Twitter blocks (lines 12–13). Each group is in time order, but the merged array in a section is not in one continuous time order.
- **`excluded_records` runs two times for each platform.** The memoization is on `excluded_*_ids` and `excluded_*_thread_roots`, not on `excluded_records` itself. This gives four exclusion queries in total. It is a small cost, but you can remove it with a memoized lookup by model.
