# The `build_blocks` method

The `build_blocks` method is in the class `Edition::DraftQuery`. The method
makes a list of `DraftBlock` items. Each `DraftBlock` item holds one thread. A
thread is a set of posts that are related. The same code operates on Bluesky
posts and on Twitter tweets.

## The data that the method receives

The method receives three items of data:

- `records`: a list of posts or tweets from the database.
- `timestamp_method`: the name of the method that gives the time of a record.
- `thread_key`: a function that gives the thread name of a record.

The method does not know the type of the records. The `timestamp_method` name
and the `thread_key` function supply that data. Because of this, the method
`bluesky_blocks` and the method `twitter_blocks` use the same code.

## Step 1: The method makes groups

The method uses the `thread_key` function on each record. The function gives a
thread name. Records with the same thread name go into the same group. The
method keeps only the groups. The method does not keep the thread names.

## Step 2: The method makes one block from each group

The method does these steps for each group:

1. The method puts the records of the group in order of time. The record with
   the oldest time is first.
2. The method finds the root record. The root record is the first record of
   the thread.
3. The method makes a `DraftBlock` item. The item holds the root record and
   the other records of the group.

To find the root record, the method compares two values for each record. The
first value is the thread name from the `thread_key` function. The second value
comes from the `root_identifier` method. For a Bluesky post, that value is the
`uri` value. For a tweet, that value is the `tweet_id` value.

If the two values are the same, that record started the thread. The method uses
that record as the root record. If no record has two values that are the same,
the method uses the record with the oldest time.

The `thread_members` list holds all the records of the group but not the root
record. The records stay in order of time. If a group has only one record, the
`thread_members` list is empty.

## Step 3: The method puts the blocks in order

At the end, the method puts all the blocks in order of time. For each block,
the method reads the time of the root record. The method uses the
`timestamp_method` name for this. The block with the oldest root record is
first. This list of blocks is the result of the method.
