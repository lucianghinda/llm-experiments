[`Edition::DraftQuery`](<app-root>/app/services/edition/draft_query.rb:3) collects Bluesky posts and Twitter tweets for one newsletter edition.

### Result

The service returns a Ruby hash.

- Each key identifies one top-level newsletter section.
- Each value contains an array of `DraftBlock` objects.
- Empty sections stay in the hash.

A `DraftBlock` has two fields:

- `root`: The main post in a thread.
- `thread_members`: The other posts in the thread.

### Operation

1. The service creates all newsletter sections in taxonomy order.

2. The service calculates a time range. The range starts at the beginning of `start_date`. It stops at the beginning of the day after `end_date`. Thus, the range includes all of both dates.

3. The service gets posts from the edition organization. It processes Bluesky posts and Twitter tweets separately.

4. Each query selects records that:

   - Are in the time range.
   - Are not hidden.
   - Do not have an individual exclusion.
   - Do not belong to an excluded thread.

5. Rails also loads URL titles, author accounts, and snapshot images. This action reduces later database queries.

6. The service groups records into threads.

   - Bluesky uses `thread_root_uri`. It uses `uri` when `thread_root_uri` is empty.
   - Twitter uses `conversation_id`. It uses `tweet_id` when `conversation_id` is empty.

7. The service sorts each thread by its creation time.

8. The service finds the root record. A root has a thread key that equals its own identifier. If the root is not available, the earliest available record becomes the root.

9. The service puts all other records in `thread_members`.

10. The service uses the root section to find the top-level newsletter section. It then adds the block to that section.

### Exclusions

An exclusion for one thread member removes only that member.

An exclusion for a thread root removes the complete thread. The service detects a root with these rules:

- A Bluesky root has `thread_root_uri == uri`.
- A Twitter root has `conversation_id == tweet_id`.

### Ordering detail

The service sorts Bluesky blocks by root time. It also sorts Twitter blocks by root time.

The service adds all Bluesky blocks before all Twitter blocks. Therefore, a section does not have one combined chronological order across both sources.

### Database detail

The root exclusion queries use SQL `NOT IN`. When an exclusion list is not empty, PostgreSQL does not select rows with a `NULL` thread key. Thus, records with a null `thread_root_uri` or `conversation_id` can also disappear.