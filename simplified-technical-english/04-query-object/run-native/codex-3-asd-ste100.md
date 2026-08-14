`Edition::DraftQuery` prepares social-media posts for one newsletter edition.

The constructor stores the edition. The `call` method returns an ordered hash of newsletter sections. Each section contains an array of `DraftBlock` objects.

A `DraftBlock` has two fields:

- `root` contains the main post in a thread.
- `thread_members` contains the other posts in time order.

The query uses the edition start date and end date. The time range starts at midnight on the start date. It stops before midnight after the end date.

The service gets Bluesky posts and Twitter tweets from the edition organization. For each platform, it:

1. Selects records in the time range.
2. Selects records that are not hidden.
3. Removes records that the edition excludes.
4. Removes the full thread when the excluded record is the thread root.
5. Loads related URLs, authors, platform accounts, and snapshot images.
6. Sorts the records by their creation time.

The service groups Bluesky posts by `thread_root_uri`. It uses the post URI when `thread_root_uri` is empty.

The service groups Twitter tweets by `conversation_id`. It uses the tweet ID when `conversation_id` is empty.

For each group, the service sorts the records by time. It finds the record whose identifier matches the thread identifier. This record becomes the root. If the service cannot find that record, the first record becomes the root.

The service removes the root from the thread-member list. It then sorts all blocks by the creation time of their roots.

The service uses the section of each root to find a newsletter section key. It skips the block when the result does not contain that top-level section. Otherwise, it adds the block to that section.

The service adds all Bluesky blocks before all Twitter blocks. Thus, records from the two platforms do not have one combined time order.

The service saves exclusion results in memory during one call. This action prevents repeated work in the related exclusion methods.
