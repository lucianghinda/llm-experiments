No MCP tool fits this; the `rails_*` tools are not connected in this session, so I used `Read` on the file you named.

# `Edition::DraftQuery`

The class builds the draft content of a newsletter edition. It groups social posts into threads, and puts each thread into a newsletter section.

## Public interface

`Edition::DraftQuery.new(edition).call`

The result is a Hash. The keys are the top-level section keys from `Newsletter::SectionTaxonomy.ordered_top_level`. Each value is an Array of `DraftBlock` items.

`DraftBlock` is a `Data` type with two members:
- `root` — the first post of the thread.
- `thread_members` — the other posts of the thread, in time sequence.

## Sequence of operations

1. `empty_sections` makes a Hash with one empty Array for each top-level section.
2. `bluesky_blocks` collects the Bluesky posts and makes blocks.
3. `twitter_blocks` collects the tweets and makes blocks.
4. `add_blocks` puts each block into the correct section.

## Selection of records (lines 29–55)

The two methods are equivalent. Each method does these steps:

- It reads the posts of the edition organisation.
- It keeps the records in the time `window` (line 26). The window starts at the beginning of `start_date`, and ends before the beginning of the day after `end_date`. The three dots make the end exclusive.
- It removes hidden records.
- It removes records that the edition excludes (`excluded_bluesky_ids` / `excluded_twitter_ids`).
- It removes all records of an excluded thread (`without_*_root_exclusions`).
- It preloads the associations: link titles, the author with the platform accounts, and the snapshot image with its blob. This prevents N+1 queries.
- It sorts the records by creation time.

## Exclusions (lines 95–129)

`edition_exclusions` is a polymorphic association. `excluded_records` reads the excluded objects for one model.

There are two levels of exclusion:

- **Record level** — the ID of the excluded post. The query removes only this post.
- **Thread level** — an excluded post is a thread root when its `thread_root_uri` is equal to its own `uri` (Bluesky), or its `conversation_id` is equal to its own `tweet_id` (Twitter). In this condition, the query removes all posts of that thread.

The `without_*` methods do not add a condition when the list is empty. This is necessary, because `where.not(column: [])` gives no result restriction, but an empty `IN` list can cause unwanted behaviour with `NOT IN` and NULL values.

## Thread grouping (lines 57–67)

`build_blocks` is common code for the two platforms. It receives the records, the name of the timestamp method, and a `Method` object that gives the thread key.

- The thread key is `thread_root_uri` or, if this is empty, the `uri` of the post. Twitter uses `conversation_id` or `tweet_id`.
- `group_by` puts the records of the same thread together.
- The records in each group get a sort by time.
- The root is the record whose thread key is equal to its own identifier (`uri` or `tweet_id`). This is the true first post of the thread.
- If the true first post is not in the group, the earliest record becomes the root. This occurs when the first post is outside the time window, or when it is hidden.
- The other records become `thread_members`.
- At the end, the blocks get a sort by the timestamp of their root.

## Assignment to sections (lines 78–85)

`add_blocks` reads the `section` value of the root post. `Newsletter::SectionTaxonomy.for` translates this value to a top-level key. If the key is not in the Hash, the code discards the block (line 81). The section of the thread members has no effect.

## Two points to know

- The order in `call` is important. All Bluesky blocks come before all Twitter blocks in each section. There is no mixed sort by time between the two platforms.
- `excluded_records` (line 127) makes a new database query at each call. The four memoized methods call it two times for each platform. One shared memoization of `excluded_records` per model removes two queries.
