# The class `Edition::DraftQuery`

## Purpose

The class `Edition::DraftQuery` prepares the content of one newsletter edition.
It reads the social media posts of an organisation.
Then it puts these posts into the sections of the newsletter.
The result is a Ruby `Hash`.

## Input

The class gets one `Edition` object.
The `Edition` object gives four items of data to the class:

- The organisation that owns the posts.
- The start date of the edition.
- The end date of the edition.
- The list of exclusions for this edition.

## The data structure `DraftBlock`

A `DraftBlock` is a small value object.
It holds two items of data:

- `root`. This is the first post of a thread.
- `thread_members`. This is the list of the other posts in the same thread.

## The method `call`

The method `call` does these four steps:

1. It makes an empty `Hash`. There is one key for each top level section.
2. It adds the Bluesky blocks to that `Hash`.
3. It adds the Twitter blocks to the same `Hash`.
4. It returns the `Hash`.

The method `empty_sections` gets the section keys from
`Newsletter::SectionTaxonomy.ordered_top_level`.
These keys are in the correct order for the newsletter.
The value of each key starts as an empty array.

## The time window

The method `window` makes a range of time.
The range starts at 00:00 on the start date of the edition.
The range stops at 00:00 on the day after the end date.
The last hour of the end date is thus in the range.

## How the class finds the Bluesky posts

The method `bluesky_blocks` reads the database one time.
It selects the posts that agree with all of these conditions:

- The post is a post of the organisation of the edition.
- The value of `post_created_at` is in the time window.
- The value of `hidden` is false.
- The person who makes the newsletter did not exclude the post.
- The person who makes the newsletter did not exclude the root of the thread.

The query also loads the related data at the same time.
This related data includes the URL titles, the author, the accounts of the
author, and the attached image.
This prevents a large quantity of small queries later.

The query puts the records in order of `post_created_at`.
Then it sends the records to the method `build_blocks`.

## How the class finds the tweets

The method `twitter_blocks` does the same steps for the tweets.
Only three names are different:

- The column of the date is `tweet_created_at` and not `post_created_at`.
- The column of the thread is `conversation_id` and not `thread_root_uri`.
- The column of the identity is `tweet_id` and not `uri`.

## How the class makes the blocks

The method `build_blocks` is the same for the two platforms.
It gets three parameters: the records, the name of the date column, and a
function for the thread key.

The method does these steps:

1. It collects the records that have the same thread key. Each collection is one
   thread.
2. It puts the records of each thread in order of date.
3. It finds the root record of the thread.
4. It makes one `DraftBlock`. The root is the root record. The thread members
   are all the other records.
5. It puts all the blocks in order of the date of the root.

To find the root, the method compares the thread key of a record with the
identity of the same record.
If the two values are equal, that record is the root of the thread.
If the method finds no such record, it uses the first record in the order of
date.

## The thread keys

The thread key of a Bluesky post is the value of `thread_root_uri`.
If that value is empty, the thread key is the value of `uri`.

The thread key of a tweet is the value of `conversation_id`.
If that value is empty, the thread key is the value of `tweet_id`.

A post that is not a reply is thus its own root.

## How the class removes the excluded posts

The method `excluded_records` reads the `edition_exclusions` of the edition.
It selects only the exclusions of the given model.
Then it gets the related post or tweet for each exclusion.

The class makes two lists from these records:

- A list of the record identities. The query removes these records one by one.
- A list of the thread roots. The query removes all the replies to these roots.

A record is in the second list only if two conditions are true.
The value of the thread column must not be empty.
The value of the thread column must be equal to the identity of the record.
These two conditions show that the excluded record is the root of a thread.

If the second list is empty, the class does not add a condition to the query.
The methods `without_bluesky_root_exclusions` and
`without_twitter_root_exclusions` do this test.

The class keeps the four lists in instance variables.
Thus the class reads the exclusions from the database only one time for each
list.

## How the class puts the blocks into the sections

The method `add_blocks` examines each block.
It reads the value `section` of the root record.
Then it asks `Newsletter::SectionTaxonomy.for` for the section of the
newsletter.
The taxonomy gives a default section if the value is not known.

The method then puts the block at the end of the array of that section.
If the section key is not in the `Hash`, the method ignores the block.
This test is a safety condition.

## The result

The result is a `Hash`.
The keys are the section keys in the order of the newsletter.
The value of each key is an array of `DraftBlock` objects.

The class adds the Bluesky blocks before the Twitter blocks.
In each section, the Bluesky blocks are thus first and in order of date.
The Twitter blocks come after them and also in order of date.
A section can be empty.

## Notes on the behaviour

The class does two database queries for the posts.
It does one more query for each list of exclusions.
The class does all the other work in memory.

The class does not remove a thread if the root post has an empty thread column.
In that condition, the exclusion removes only the root post.
The replies stay in the newsletter and the method `build_blocks` makes the
oldest reply the new root.
