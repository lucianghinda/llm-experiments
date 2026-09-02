You asked me to read this specific file, so I used `Read` instead of an MCP tool.

## What the class does

`Edition::DraftQuery` collects the social posts for one newsletter edition. It groups the posts into threads. Then it sorts the threads into newsletter sections.

The entry point is `call` (line 10). It returns a Hash. The keys are the top-level section keys. The values are arrays of `DraftBlock` records.

## The data structure

Line 4 defines `DraftBlock`. It is a `Data` object with two fields:

- `root` — the first post of a thread.
- `thread_members` — the other posts of the same thread.

## Step 1 — Make the empty sections

`empty_sections` (line 21) asks `Newsletter::SectionTaxonomy` for the ordered top-level sections. It gives each section an empty array. The order of the Hash keys sets the order of the sections in the draft.

## Step 2 — Find the time window

`window` (line 25) makes an exclusive range. It starts at the beginning of `edition.start_date`. It ends at the beginning of the day after `edition.end_date`. Thus the last day is fully included.

## Step 3 — Get the records

`bluesky_blocks` (line 29) and `twitter_blocks` (line 43) are the same in structure. Each method does these operations:

1. It starts from the posts or the tweets of the organisation.
2. It keeps only the records in the time window that are not hidden.
3. It removes the records that the editor excluded, by ID.
4. It removes all records whose thread root is excluded (line 33 and line 47).
5. It preloads the associations, to prevent N+1 queries.
6. It sorts the records by the creation time.

The two methods are different only in the column names: `post_created_at` against `tweet_created_at`, and the thread key method.

## Step 4 — Group the records into threads

`build_blocks` (line 57) does the thread logic:

- It groups the records with the thread key. For Bluesky, the key is `thread_root_uri`, or the URI of the post if the post has no root (line 87). For Twitter, the key is `conversation_id`, or the tweet ID (line 91).
- In each group, it sorts the records by time.
- It finds the true root. The root is the record whose own identifier is equal to the thread key (line 60). If the query did not find the root record, the method uses the first record as the root (line 62).
- It makes a `DraftBlock` with this root and the remaining records.
- Last, it sorts all blocks by the time of their root.

`root_identifier` (line 69) gives the identifier for the comparison: `uri` for a Bluesky post, `tweet_id` for a tweet.

## Step 5 — Put the blocks into the sections

`add_blocks` (line 78) reads the `section` value of the root post. It converts this value into a section key with `Newsletter::SectionTaxonomy.for(...)`. If the key is not one of the top-level sections, the method ignores the block (line 81). If the key is correct, the method adds the block to that section.

## The exclusions

The four `excluded_*` methods read `edition.edition_exclusions`. Each method uses memoization with an underscore prefix, as your style guide specifies.

There are two types of exclusion:

- **Single record** — `excluded_bluesky_ids` and `excluded_twitter_ids` give the primary keys. The query removes only these records.
- **Full thread** — `excluded_bluesky_thread_roots` (line 111) and `excluded_twitter_thread_roots` (line 121) keep an excluded record only if the record is the root of its own thread. If an editor excludes a thread root, the query removes the full thread.

## One point to note

`excluded_records` (line 127) runs a new database query at each call. `excluded_bluesky_ids` and `excluded_bluesky_thread_roots` both call it for `Bluesky::Post`. Thus the same query runs two times for each platform, four times in total. The memoization is on the derived arrays, not on the records. A memoized `excluded_records` would remove two queries.
