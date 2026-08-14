# The Edition::DraftQuery class

## 1. Purpose

`Edition::DraftQuery` is a query object. The class reads the social media posts of one newsletter edition. Then it puts these posts into the sections of the newsletter.

The class does three operations:

1. It selects the posts of the edition.
2. It puts the posts of one thread into one group.
3. It sends each group to the correct section.

The class has one public method with the name `call`. The method gives a hash. Each key of the hash is the name of a section. The value of each key is a list of blocks.

## 2. The DraftBlock structure

`DraftBlock` is a `Data` structure with two fields:

- `root` is the first post of a thread.
- `thread_members` is the list of the other posts of the same thread.

A thread with one post only has an empty list in `thread_members`.

## 3. The start of the operation

The method `initialize` receives one edition. The class keeps the edition in an instance variable. A private reader gives access to this variable. The class does no database operation at this time.

The method `call` does four steps:

1. It makes an empty hash with one key for each top-level section.
2. It adds the Bluesky blocks to this hash.
3. It adds the Twitter blocks to this hash.
4. It gives the hash.

The method `empty_sections` gets the section keys from `Newsletter::SectionTaxonomy.ordered_top_level`. These keys are in the sequence of the newsletter. The method `index_with { [] }` makes an empty list for each key. Thus the sections in the result are always in the correct sequence. A section without posts stays in the result with an empty list.

## 4. The time window

The method `window` makes a range of times:

- The range starts at 00:00 on the start date of the edition.
- The range ends at 00:00 on the day after the end date.

The three dots make the last value exclusive. Thus the range contains all the times of the end date, but not the first moment of the subsequent day. The edition includes the full last day.

## 5. The two database queries

The method `bluesky_blocks` makes a query on the Bluesky posts of the organisation. The query has these conditions:

1. The value of `post_created_at` is in the time window.
2. The value of `hidden` is false.
3. The ID of the post is not in the list of the excluded IDs.
4. The thread root of the post is not in the list of the excluded thread roots.

The query also reads four related records in advance: the URL titles, the author, the platform accounts of the author, and the snapshot image with its blob. This prevents a large quantity of small queries.

The query puts the records in the sequence of `post_created_at`. The method `to_a` sends the query to the database. All the subsequent operations occur in memory.

The method `twitter_blocks` is the same method for the tweets. It uses the column `tweet_created_at` in the place of `post_created_at`. The two methods are equivalent, but the column names and the model names are different.

## 6. The thread key

Each platform has a different name for the first post of a thread:

| Platform | Key of the thread | Identifier of the record |
| --- | --- | --- |
| Bluesky | `thread_root_uri` | `uri` |
| Twitter | `conversation_id` | `tweet_id` |

The method `bluesky_thread_key` gives the value of `thread_root_uri`. If this value is empty, the method gives the value of `uri`. The method `twitter_thread_key` does the same operation with `conversation_id` and `tweet_id`.

Thus all the posts of one thread have the same key. A post without a thread is its own key.

## 7. How the class makes the blocks

The method `build_blocks` is the same for the two platforms. The caller supplies two parameters: the name of the time column and the method for the thread key. Thus one algorithm is sufficient for the two platforms.

The method does these steps:

1. It puts the records into groups. All the records of one group have the same thread key.
2. In each group, it puts the records in the sequence of their time.
3. It finds the root of the group.
4. It makes a `DraftBlock` with this root. The other records become the thread members.
5. It puts all the blocks in the sequence of the time of their root.

For step 3, the method compares the thread key of each record with the identifier of the same record. If the two values are equal, the record is the root. If no record obeys this condition, the method uses the first record in the time sequence. This condition occurs when the true root is not in the database, or when the true root is outside of the time window.

## 8. How the class puts the blocks into the sections

The method `add_blocks` examines each block. It does these steps:

1. It reads the `section` value of the root post.
2. `Newsletter::SectionTaxonomy.for` changes this value into a top-level section.
3. `fetch(:key)` gives the key of that section.
4. If the hash does not contain this key, the method discards the block.
5. If the hash contains this key, the method adds the block to the end of the list.

Only the section of the root is applicable. The other posts of the thread go to the section of the root.

The taxonomy has a default value. If the section of the post is unknown or empty, the taxonomy uses the section `post`. This section maps to the key `code_and_ruby`. Thus the taxonomy always gives a top-level key, and the test in step 4 is a protection only.

The method `call` adds the Bluesky blocks before the Twitter blocks. Thus in each section, all the Bluesky blocks are before all the Twitter blocks. Each of the two groups is in its own time sequence. The class does not mix the two platforms in one time sequence.

## 9. The exclusions

A user can remove a post from an edition. The table `edition_exclusions` keeps these decisions. Each row has a polymorphic reference to a post or to a tweet.

The method `excluded_records` reads the exclusions for one model. It gives the related records. Four other methods use this result:

- `excluded_bluesky_ids` gives the IDs of the excluded posts.
- `excluded_twitter_ids` gives the IDs of the excluded tweets.
- `excluded_bluesky_thread_roots` gives the URI of an excluded post, but only if that post is the root of its thread.
- `excluded_twitter_thread_roots` does the same operation for the tweets.

The two methods for the roots make a test with two conditions. The value of `thread_root_uri` must have content, and it must be equal to the value of `uri`. The test for the tweets uses `conversation_id` and `tweet_id`.

This behavior is important. If the user removes one post of a thread, the query removes that post only. If the user removes the root of a thread, the query removes all the posts of that thread. The full thread has no more sense without its first post.

The methods `without_bluesky_root_exclusions` and `without_twitter_root_exclusions` add the condition for the thread roots. If the list of the excluded roots is empty, these methods give the query without a change. This prevents an unnecessary condition in the SQL.

Each of the four methods keeps its result in an instance variable. Thus the database operation occurs one time only for each instance of the class.

## 10. Summary of the rules

| Condition | Result |
| --- | --- |
| The post is outside of the time window | The query does not select the post. |
| The value of `hidden` is true | The query does not select the post. |
| The user excluded the post | The query does not select the post. |
| The user excluded the root of the thread | The query does not select any post of that thread. |
| Two or more posts have the same thread key | The class makes one block with one root. |
| The root of the thread is not available | The class uses the first post in the time sequence. |
| The section of the post is unknown | The class uses the section `code_and_ruby`. |
| A section has no posts | The section stays in the result with an empty list. |
