# `build_blocks` (app/services/edition/draft_query.rb:57)

## Function

The method makes groups of social posts. Each group is one thread. It gives one `DraftBlock` for each thread. The result is a list of blocks in time sequence.

## Parameters

| Parameter | Function |
|---|---|
| `records` | The posts or the tweets. They are already an array. |
| `timestamp_method` | The name of the time attribute (`:post_created_at` or `:tweet_created_at`). |
| `thread_key` | A `Method` object. It gives the thread identifier of one record. |

The two callers give different values. Thus the same code operates on Bluesky posts (line 40) and on Twitter tweets (line 54).

## Steps

**1. Group the records into threads (line 58).**
`group_by` calls `thread_key` on each record. `bluesky_thread_key` (line 87) gives `thread_root_uri`, or `uri` if the root is empty. `twitter_thread_key` (line 91) gives `conversation_id`, or `tweet_id`. Thus all records of one thread receive the same key. A single post is a group with one member. `.values` removes the keys and keeps only the arrays of records.

**2. Sort each thread (line 59).**
`sort_by(&timestamp_method)` puts the records of the thread in time sequence. The `&` operator makes a block from the `Method` object.

**3. Find the root record (lines 60–62).**
A record is the root when its thread key is equal to its own identifier. `root_identifier` (line 69) gives `uri` for a Bluesky post and `tweet_id` for a tweet. If no record agrees with this condition, the code uses `ordered_records.first` — the first record in time.

> This is necessary because the root post can be absent. The window (line 26) or the exclusions can remove it.

**4. Make the block (line 63).**
`DraftBlock` is a `Data` object with two fields (line 4). `root` is the root record. `thread_members` is `ordered_records - [root]`: all the other records of the thread, in time sequence.

**5. Sort the blocks (line 66).**
The blocks go in the sequence of the timestamp of their root. `public_send` is necessary here, because the code has a block variable and not a simple symbol-to-proc.

## Result

`call` (line 10) sends these blocks to `add_blocks` (line 78). That method puts each block in a newsletter section. It uses the `section` value of the root record.
