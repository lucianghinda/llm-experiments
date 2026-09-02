## What the method does

`build_blocks` (app/services/edition/draft_query.rb:57) changes a flat list of social posts into a list of threads. Each thread becomes one `DraftBlock` (line 4): one root record, plus the other records of the same thread.

## The three parameters

- `records` — the posts or the tweets, already sorted by time.
- `timestamp_method` — the name of the time column (`:post_created_at` or `:tweet_created_at`).
- `thread_key` — a `Method` object that gives the thread identity of a record (line 40 and line 54).

The two callers give different values. Thus the same method operates on `Bluesky::Post` and on `Twitter::Tweet`.

## The steps

**1. Group the records into threads (line 58).**
`group_by` applies `thread_key` to each record. For Bluesky, the key is `thread_root_uri`, or the post `uri` if `thread_root_uri` is empty (line 88). For Twitter, the key is `conversation_id`, or the `tweet_id` (line 92). All records of one thread get the same key. `.values` keeps only the groups, not the keys.

**2. Sort each group by time (line 59).**
The records of the thread go into chronological order.

**3. Find the root of the thread (lines 60–62).**
A record is the root if its thread key is equal to its own identifier. `root_identifier` gives the `uri` for a Bluesky post and the `tweet_id` for a tweet (lines 69–76). Thus the root is the record that points to itself.

If no record agrees with this condition, the code uses the first record in time (`|| ordered_records.first`, line 62). This occurs when the true root is not in the window, or an exclusion removed it.

**4. Make the block (line 63).**
`root:` is the record from step 3. `thread_members:` is all the other records (`ordered_records - [root]`). Array subtraction is correct here, because Active Record compares records by class and by id.

**5. Sort the blocks (line 66).**
The blocks go into chronological order by the timestamp of their root. `public_send` is necessary because `timestamp_method` is a symbol.

## Result

The method gives an array of `DraftBlock`. `add_blocks` (line 78) then puts each block into a newsletter section. The section comes from the root record only, not from the thread members.

## Two small notes

- The sort at line 59 is almost not necessary. Both callers already apply `order(...)` in the query (line 37 and line 51), and `group_by` keeps the input order. The sort makes the method safe if a caller sends unsorted records.
- Ruby `sort_by` is not stable. If two roots have the same timestamp, their relative order is not guaranteed.
