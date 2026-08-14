`Edition::DraftQuery` builds the draft content for one newsletter edition.

The service receives an `edition` when it starts. The `call` method returns a hash. Each key is a top-level newsletter section. Each value is a list of post blocks for that section.

The service does this work:

1. It creates all top-level newsletter sections with empty lists.
2. It loads Bluesky posts for the edition’s organisation.
3. It loads Twitter posts for the same organisation.
4. It groups related posts into threads.
5. It puts each thread into the correct newsletter section.

It only loads posts from the edition’s date range. The range starts at the beginning of `start_date`. It ends at the beginning of the day after `end_date`. This includes the complete end date.

The query removes hidden posts and posts that the edition excludes. If an excluded post is the root of a thread, the query removes the complete thread. An exclusion of a non-root post removes only that post.

The service also loads related URL titles, author accounts, and snapshot images with each post. This reduces extra database queries later.

For Bluesky, the thread key is `thread_root_uri`. A post without this value uses its own `uri`.

For Twitter, the thread key is `conversation_id`. A tweet without this value uses its own `tweet_id`.

For each thread, the service:

- Sorts the posts by creation time.
- Finds the root post.
- Uses the first post if it cannot find the root.
- Creates a `DraftBlock` with the root and the other thread members.

Finally, it sorts the blocks by the creation time of their root posts. It checks the section of each root post and adds the block to that newsletter section. If the section is not a valid top-level section, it skips the block.
