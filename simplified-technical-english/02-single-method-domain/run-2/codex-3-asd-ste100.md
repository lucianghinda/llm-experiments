The method [`build_blocks`](app/services/edition/draft_query.rb:57) converts social-media records into ordered thread blocks.

Definitions:

- A **record** is one Bluesky post or one Twitter tweet.
- A **thread** is a set of related records.
- A **block** contains one root record and its thread members.

The method does these steps:

1. It groups the records by their thread identifier.
2. It sorts each group by its timestamp.
3. It searches each group for the real root record.
4. The real root has a thread identifier that is equal to its own identifier.
5. If the real root is not present, the method uses the first record in time.
6. It creates one `DraftBlock` for the group.
7. The block contains the root and all other records.
8. It sorts all blocks by the timestamp of their roots.
9. It returns the sorted blocks.

Bluesky uses `post_created_at` and the Bluesky thread key. Twitter uses `tweet_created_at` and the Twitter thread key.

Important behavior: If a thread root is outside the selected date range or is excluded, the earliest available record becomes the block root. The method does not change the input records.