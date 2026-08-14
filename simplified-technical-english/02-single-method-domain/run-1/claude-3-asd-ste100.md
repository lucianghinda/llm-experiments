# The build_blocks method

## Purpose

The build_blocks method makes a list of DraftBlock objects. Each DraftBlock holds one social media thread. The method puts the threads in time sequence.

The class Edition::DraftQuery uses this method two times. The bluesky_blocks method uses it for Bluesky posts. The twitter_blocks method uses it for tweets. The method does not know the type of the records. The caller gives the necessary type information in the parameters.

## The parameters

The method has three parameters.

- `records` is an array of database records. The records are Bluesky posts or tweets.
- `timestamp_method` is the name of the method that gives the time of a record. For a Bluesky post, the name is `post_created_at`. For a tweet, the name is `tweet_created_at`.
- `thread_key` is a Ruby Method object. This object gives the thread identifier of a record. For a reply, the thread identifier is the identifier of the first record in the thread.

## Step 1. Make the groups

The method calls `thread_key` for each record. Then the method puts all the records that have the same key in one group. Each group is one thread. A record that has no reply makes a group of one record.

## Step 2. Sort each group

The method sorts the records in each group by time. The oldest record is first. The method uses the `timestamp_method` parameter to read the time of a record.

## Step 3. Find the root record

The root record is the first record in the thread. To find the root record, the method compares two values for each record in the group:

- the thread key of the record
- the identifier of the record

The `root_identifier` method gives the identifier. For a Bluesky post, the identifier is the `uri` attribute. For a tweet, the identifier is the `tweet_id` attribute.

If the two values are the same, the record is the root record. The method keeps the first record that obeys this condition.

If no record in the group obeys this condition, the method uses the oldest record as the root record. This condition can occur when the database does not contain the first record of the thread. It can also occur when a filter removed the first record.

## Step 4. Make the DraftBlock objects

The method makes one DraftBlock for each group. A DraftBlock has two fields:

- `root` holds the root record.
- `thread_members` holds the other records of the group, in time sequence.

To get the value for `thread_members`, the method removes the root record from the sorted list. If a group contains only one record, `thread_members` is an empty array.

## Step 5. Sort the blocks

At the end, the method sorts all the DraftBlock objects. The sort value is the time of the root record. The method gives this array of blocks to the caller.

## Example

A group contains three tweets:

- Tweet A has the `tweet_id` 100 and the `conversation_id` 100.
- Tweet B and tweet C have the `conversation_id` 100.

The thread key of the three tweets is 100. Thus the three tweets make one group.

The method sorts the tweets by time. The sequence is A, B, C.

Tweet A has the same `tweet_id` and thread key. Thus tweet A is the root record.

The result is one DraftBlock. The `root` field holds tweet A. The `thread_members` field holds tweet B and tweet C.
