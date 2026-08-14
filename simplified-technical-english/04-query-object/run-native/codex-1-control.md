`Edition::DraftQuery` builds the content for an edition draft from Bluesky posts and tweets.

It returns a hash whose keys are the newsletter’s ordered top-level sections. Every section is present, even when empty. Each value is an array of `DraftBlock` objects, where a block contains:

- `root`: the post or tweet representing the thread
- `thread_members`: the remaining items in that thread, ordered by publication time

The query works as follows:

1. It creates the empty section hash from `Newsletter::SectionTaxonomy.ordered_top_level`.
2. It fetches eligible Bluesky posts belonging to the edition’s organisation.
3. It fetches eligible tweets in the same way.
4. It groups each platform’s records into threads.
5. It assigns every thread block to the section determined by its root record.

Eligible records must:

- Have been published between the beginning of `edition.start_date` and the beginning of the day after `edition.end_date`. This half-open range includes the entire end date.
- Have `hidden: false`.
- Not be explicitly excluded from the edition.

Exclusions have two levels. Excluding an ordinary reply removes only that record. When the excluded record identifies itself as a thread root—its Bluesky `thread_root_uri` equals its own `uri`, or its Twitter `conversation_id` equals its own `tweet_id`—the query also removes records belonging to that entire thread.

For Bluesky, the thread key is `thread_root_uri`, falling back to the post’s own `uri`. For Twitter, it is `conversation_id`, falling back to the tweet’s own `tweet_id`.

Within each group, records are sorted chronologically. The query looks for the true root by finding the record whose own identifier matches the thread key. If the root is absent, it promotes the earliest remaining record to root. The other records become `thread_members`. Blocks are then ordered by their root timestamps.

The queries eager-load URL titles, author and platform-account data, and snapshot-image attachments to avoid additional database queries when the draft is rendered.

A whole thread is classified using the root record’s `section`. If that section does not correspond to one of the initialized top-level section keys, the block is skipped. Bluesky blocks are appended before Twitter blocks, so each platform is internally chronological, but the combined section contents are not globally sorted across both platforms.

The exclusion ID and root lists are memoized for the lifetime of the query object so repeated uses within one call do not recalculate those arrays.
