`build_blocks` converts posts or tweets into ordered thread blocks.

It receives:

- `records`: the posts or tweets.
- `timestamp_method`: the timestamp field to use.
- `thread_key`: a method that identifies the thread for each record.

First, it groups the records by their thread identifier.

For each group, it:

1. Sorts the records by time.
2. Looks for the thread root. A record is the root when its thread identifier is the same as its own identifier.
3. Uses the earliest record if the real root is not present.
4. Creates a `DraftBlock`. The block contains the root and all other records as `thread_members`.

Finally, it sorts all blocks by the time of their root record and returns the sorted blocks.
