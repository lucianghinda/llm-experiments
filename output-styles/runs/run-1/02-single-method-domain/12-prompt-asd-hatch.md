## `build_blocks` — what it does

`app/services/edition/draft_query.rb:57`

It takes a flat list of social posts and makes a list of **thread blocks**. Each block has one root post and its replies. It then sorts the blocks by time.

### Parameters

| Parameter | Type | Function |
|---|---|---|
| `records` | Array of `Bluesky::Post` or `Twitter::Tweet` | The posts in the edition window. |
| `timestamp_method` | Symbol (`:post_created_at` or `:tweet_created_at`) | The name of the time attribute. |
| `thread_key` | `Method` object | Gives the thread identity of a post. |

The two callers (`bluesky_blocks:40`, `twitter_blocks:54`) supply different values. Thus the same procedure operates on both platforms.

### Steps

**1. Group the posts into threads** (line 58)

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`thread_key` is `bluesky_thread_key:87` or `twitter_thread_key:91`. Each one gives the thread root identifier, or the post's own identifier if the post has no root. Therefore a post that is not in a thread makes a group of one.

**2. Sort each group by time** (line 59)

`ordered_records` holds the posts of one thread, oldest first.

**3. Find the root post** (lines 60–62)

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } || ordered_records.first
```

`root_identifier:69` gives the post's own identifier (`uri` for Bluesky, `tweet_id` for Twitter). The test is true only for the post that is its own thread root.

If no post satisfies the test, the code uses the oldest post. This condition occurs when the true root is not in `records` — for example, the root is hidden, excluded, or outside the date window.

**4. Make the block** (line 63)

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a `Data` type (line 4). `thread_members` holds the remaining posts, oldest first. For a single post, `thread_members` is empty.

**5. Sort the blocks** (line 66)

The code sorts all blocks by the timestamp of their root post. The output is thus in chronological order, and the reply order in each thread stays correct.

### Result

For an input of 5 posts — 3 posts in one thread and 2 independent posts — the output is 3 blocks: one block with a root and 2 thread members, and two blocks with no thread members.
