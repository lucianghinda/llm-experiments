`build_blocks` is at `app/services/edition/draft_query.rb:57`. It changes a flat list of posts into a list of threads. Each thread becomes one `DraftBlock`.

## The three parameters

| Parameter | Content | Example |
|---|---|---|
| `records` | The flat list of posts or tweets from the query | Bluesky posts in the edition window |
| `timestamp_method` | The name of the time column, as a symbol | `:post_created_at` or `:tweet_created_at` |
| `thread_key` | A `Method` object. It gives the thread identifier of a record | `method(:bluesky_thread_key)` |

The two callers (`bluesky_blocks` at line 40, `twitter_blocks` at line 54) send different values. Thus the same code operates on the two platforms.

## The four steps

**1. Group the records into threads** (line 58)

`group_by` calls `thread_key` on each record. For Bluesky, `bluesky_thread_key` gives `thread_root_uri` if this value is present. If not, it gives the post `uri` (line 88). For Twitter, the equivalent values are `conversation_id` and `tweet_id` (line 92). Therefore all posts of one thread get the same key, and a single post makes its own group. `.values` keeps only the groups, and not the keys.

**2. Sort the records in each thread** (line 59)

`sort_by(&timestamp_method)` puts the records of the thread in chronological order.

**3. Find the root of the thread** (lines 60-62)

The code looks for the record whose thread key is equal to its own identifier. `root_identifier` gives the `uri` for a Bluesky post, and the `tweet_id` for a tweet (line 69). A record that satisfies this condition points to itself. Thus it is the first post of the thread.

If no record satisfies the condition, the `||` operator selects `ordered_records.first`. This occurs when the true root is not in the result set. For example, the root is outside the date window of the edition, or a user hid it.

**4. Make the block** (line 63)

`DraftBlock` is a `Data` object with two fields (line 4). The `root` field holds the first post. The `thread_members` field holds all the other records, in chronological order. `ordered_records - [root]` removes the root from the list.

## The result

Line 66 sorts the blocks by the timestamp of each root. The method gives back one block for each thread, in chronological order. Subsequently, `add_blocks` (line 78) puts each block in a newsletter section. It uses the section of the root record only.
