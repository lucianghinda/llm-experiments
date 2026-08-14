`build_blocks` turns a flat list of posts or tweets into chronologically ordered thread blocks.

It takes:

- `records`: the posts or tweets
- `timestamp_method`: the timestamp field, such as `:post_created_at`
- `thread_key`: a callable that returns the thread or conversation identifier

First, it groups records that share the same thread key. Within each group, it sorts the records by timestamp.

It then identifies the thread root by finding the record whose own identifier—its Bluesky URI or Twitter tweet ID—matches the thread key. If the actual root is missing, perhaps because it falls outside the edition window or was filtered out, the earliest available record becomes the root.

Each group becomes a `DraftBlock` containing:

- `root`: the detected root or earliest available record
- `thread_members`: the remaining records, still in chronological order

Finally, it sorts all blocks by their roots’ timestamps, so the result is a chronological list of threads rather than individual posts.
