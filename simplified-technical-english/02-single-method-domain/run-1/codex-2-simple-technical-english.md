[`build_blocks`](app/services/edition/draft_query.rb:57) turns a flat list of posts or tweets into ordered conversation blocks.

It works like this:

1. **Group records by thread.**
   - Bluesky records use their thread root URI.
   - Twitter records use their conversation ID.
   - Standalone records use their own ID, so each becomes a separate group.

2. **Sort each group by time.**
   `timestamp_method` is either `post_created_at` or `tweet_created_at`.

3. **Find the root record.**
   It looks for the record whose own ID matches the thread’s root ID.

4. **Handle a missing root.**
   If the actual root is unavailable—perhaps outside the edition’s date range—the earliest available record becomes the root.

5. **Create a `DraftBlock`.**
   Each block contains:
   - `root`: the root or earliest record
   - `thread_members`: every other record, in time order

6. **Sort all blocks by their roots’ timestamps.**

In simplified pseudocode:

```text
group records by conversation
for each conversation:
    sort its records by time
    choose the real root, or the earliest record
    create a block containing the root and remaining members
sort all blocks by root time
```

So its main purpose is to convert individual social-media records into chronological, root-led conversation blocks suitable for the newsletter draft.