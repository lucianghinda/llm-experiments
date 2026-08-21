# The method `build_blocks`

## Function of the method

The method makes a list of `DraftBlock` objects from a flat list of records.

Each `DraftBlock` holds one thread. A thread has one root record and zero or more member records. The method returns the blocks in time sequence, and the oldest thread is first.

The method does not read the database. It operates only on the records that the caller supplies.

## The three parameters

The method has three parameters:

- `records` — an array of records from one platform. The caller reads these records from the database before it calls the method.
- `timestamp_method` — the name of the time attribute of a record. The value is `:post_created_at` or `:tweet_created_at`.
- `thread_key` — a `Method` object. It gives the thread identifier of a record.

The two callers supply different values. The method `bluesky_blocks` supplies `:post_created_at` and the method `bluesky_thread_key`. The method `twitter_blocks` supplies `:tweet_created_at` and the method `twitter_thread_key`.

Because of these parameters, one method is sufficient for the two platforms. The method does not examine the class of the records.

## Step 1: the method puts the records into groups

The code `records.group_by { |record| thread_key.call(record) }` puts all records with the same thread key into the same group.

For a Bluesky post, the thread key is the `thread_root_uri`. If the `thread_root_uri` is empty, the thread key is the `uri` of the post.

For a tweet, the thread key is the `conversation_id`. If the `conversation_id` is empty, the thread key is the `tweet_id`.

A record that has no parent is thus a thread of one record.

The code `.values` removes the keys. The result is an array of arrays. Each inner array is one thread.

## Step 2: the method sorts each thread

The code `thread_records.sort_by(&timestamp_method)` sorts the records of one thread by time. The oldest record is first. The variable `ordered_records` holds this result.

## Step 3: the method finds the root record

The method looks for the record whose own identifier is the same as the thread key.

The method `root_identifier` supplies the identifier:

- the `uri` for a Bluesky post
- the `tweet_id` for a tweet

A record is the root when the thread points to that record itself. This record is the record that starts the thread.

## Step 4: the second choice for the root

The operator `||` gives a second choice. If the search finds no root record, the method uses the oldest record of the group.

This condition happens when the real root is not in `records`. There are three causes:

- the root has the flag `hidden`
- an exclusion of the edition removes the root
- the date of the root is not in the time window of the edition

Because of this second choice, each block always has a root. The method keeps a thread even when the first record of that thread is not available.

## Step 5: the method makes the block

The code `DraftBlock.new(root: root, thread_members: ordered_records - [root])` makes one block.

The operation `- [root]` removes the root record from the sorted list. The other records become the thread members. These members stay in time sequence.

## Step 6: the method sorts the blocks

The code `blocks.sort_by { |block| block.root.public_send(timestamp_method) }` sorts the blocks by the time of the root record.

The method `public_send` calls the time attribute by its name, because the name is different for the two platforms.

## The result

The method returns an array of `DraftBlock` objects in time sequence.

The caller sends this array to the method `add_blocks`. That method puts each block into the correct section of the newsletter.
