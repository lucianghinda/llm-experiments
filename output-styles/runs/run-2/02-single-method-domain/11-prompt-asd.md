I read the file directly: no MCP tool fits this, because you named the exact file and method to read, and I must quote its logic line by line.

Here is `build_blocks` (`app/services/edition/draft_query.rb:57`), explained in ASD-STE100 Simplified Technical English.

## Purpose

The method makes a list of `DraftBlock` objects. Each `DraftBlock` shows one thread of social posts. One post is the root. The other posts are the replies in the thread.

Two other methods call `build_blocks`: `bluesky_blocks` and `twitter_blocks`. Each method sends different data. Thus the same code operates on Bluesky posts and on tweets.

## The three inputs

1. `records` is the list of posts to process.
2. `timestamp_method` is the name of the time field. For Bluesky, the field is `post_created_at`. For Twitter, the field is `tweet_created_at`.
3. `thread_key` is a function. The function gives the thread identifier of one post.

## The steps

1. The method puts the records in groups. It calls the `thread_key` function for each record. Records with the same key go in the same group. Each group is one thread.
2. The method sorts the records in each group. It sorts by the time field. The oldest record is first.
3. The method finds the root record in the group. The root record is the record with a thread key that agrees with its own identifier. For a Bluesky post, the identifier is the `uri`. For a tweet, the identifier is the `tweet_id`.
4. If the method does not find such a record, it uses the first record of the sorted group. The first record is the oldest record.
5. The method makes one `DraftBlock`. The `DraftBlock` holds the root record and the other records of the group. The other records stay in time sequence.
6. The method does steps 2 to 5 again for each group.
7. The method sorts all the blocks. It sorts by the time of the root record of each block.
8. The method gives the sorted list of blocks to the caller.

## Notes on the conditions

- Step 4 is necessary when the newsletter window does not contain the first post of a thread. Then no record is the true root. The method uses the oldest available record in its place.
- In step 5, the operation `ordered_records - [root]` removes the root record from the list of members. Only the replies stay.
- `root_identifier` gives no value for a different type of record. Then no record can be the root, and step 4 applies.
