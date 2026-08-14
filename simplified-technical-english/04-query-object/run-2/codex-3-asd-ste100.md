[Edition::DraftQuery](app/services/edition/draft_query.rb:3) prepares social-media content for an edition draft.

A “record” means one Bluesky post or one tweet. A “block” contains a root record and its thread members.

### Main process

1. The service creates an empty list for each top-level newsletter section.
2. It selects records from the edition’s organisation.
3. It uses the start date and the end date as the time range.
4. It removes hidden records and excluded records.
5. It groups the remaining records into threads.
6. It puts each thread into the section of its root record.
7. It returns all sections, including empty sections.

### Date range

The range starts at the beginning of `start_date`.

The range stops before the day after `end_date`. Thus, it includes the complete end date.

### Record selection

The service processes Bluesky posts and tweets separately.

For each platform, it:

- Selects records inside the date range.
- Selects records where `hidden` is false.
- Removes records that have an edition exclusion.
- Removes all members of an excluded root thread.
- Loads related URLs, author accounts, and snapshot images.
- Orders records from oldest to newest.

The related-data load reduces later database queries.

### Thread construction

Bluesky uses `thread_root_uri` as the thread identifier. A post uses its own `uri` when no root URI exists.

Twitter uses `conversation_id` as the thread identifier. A tweet uses its own `tweet_id` when no conversation ID exists.

For each thread, the service:

1. Orders the records by creation time.
2. Finds the real root record.
3. Uses the earliest record when the real root is not available.
4. Creates a `DraftBlock`.
5. Stores all other records in `thread_members`.

### Section placement

The root record controls the section of the complete thread.

The service converts `root.section` to a newsletter section key. It skips the block when the key is not a top-level section.

### Result order

Thread members have chronological order.

Blocks from one platform have chronological order by root time.

Bluesky blocks come before Twitter blocks in each section. The service does not combine both platforms into one chronological order.

The result has this structure:

```text
section key
  └── list of DraftBlock
        ├── root
        └── thread_members
```