# Edition::DraftQuery

## What the class does

`Edition::DraftQuery` reads the social posts of one newsletter edition.
It puts these posts into the sections of the newsletter draft.
The class does not change data.
It only reads data and gives a result.

## How to use the class

The class has two public parts:

- `new(edition)` — you give the class one `Edition` record.
- `call` — this method does the work and gives the result.

Three parts of the application use the class:

- `EditionsController`, to show the draft on the screen.
- `Newsletter::SummarizeEditionPostsJob`, to make a summary of each post.
- `Newsletter::EditionMarkdown`, to write the Markdown text of the newsletter.

## The result

`call` gives a Hash.
Each key is a section key, for example `launches`, `articles` or `videos`.
Each value is a list of `DraftBlock` items.

The Hash always has all 11 sections of `Newsletter::SectionTaxonomy`.
The sections are in the sequence of the newsletter.
A section with no posts has an empty list.

## The DraftBlock

`DraftBlock` is a small data object with two fields:

- `root` — the first post of a thread.
- `thread_members` — the other posts of the same thread, in time sequence.

A post that is not part of a thread makes a block with an empty `thread_members` list.

## Step 1 — the empty sections

`empty_sections` asks `Newsletter::SectionTaxonomy` for the top-level sections.
The taxonomy gives the sections in their correct sequence.
The method makes a Hash with one empty list for each section.
`call` then puts the blocks into this Hash.

## Step 2 — the time window

`window` makes the period of time of the edition:

- It starts at the first moment of `edition.start_date`.
- It stops before the first moment of the day after `edition.end_date`.

Thus the window contains all of the last day.
The class uses the same window for the two platforms.

## Step 3 — the database read

`bluesky_blocks` and `twitter_blocks` do the same work for two different platforms.
Each method reads the records of the organisation of the edition.
A record must agree with these four conditions:

- The time of the post is in the window.
- The field `hidden` is false.
- The id of the record is not in the list of removed ids.
- The thread root of the record is not in the list of removed thread roots.

Each method also reads the related data at the same time:
the URL titles, the author with the platform accounts, and the snapshot image.
This prevents many small database reads later.
The method then puts the records in time sequence and gets them as an Array.

## Step 4 — the rules that remove posts

The edition has `edition_exclusions` records.
Each exclusion record points to one Bluesky post or to one tweet.
`excluded_records` reads these records for one model type.

The class makes two lists from these records:

- A list of ids. The database read removes these records.
- A list of thread roots. The database read removes all posts of these threads.

A record is a thread root in these two conditions:

- For Bluesky, the field `thread_root_uri` is equal to the field `uri`.
- For Twitter, the field `conversation_id` is equal to the field `tweet_id`.

As a result, if the user removes the first post of a thread, the class removes the full thread.
The four list methods keep their result in memory.
Thus the class reads the exclusion records one time only.

`without_bluesky_root_exclusions` and `without_twitter_root_exclusions` have a safety test.
If the list of thread roots is empty, they give the database query back with no change.
This prevents an SQL condition with an empty list.

## Step 5 — the blocks

`build_blocks` does the same work for the two platforms.
It gets three items:

- the records;
- the name of the time field (`post_created_at` or `tweet_created_at`);
- a method that gives the thread key of a record.

The thread key is:

- `thread_root_uri` for a Bluesky post, or `uri` if `thread_root_uri` is empty;
- `conversation_id` for a tweet, or `tweet_id` if `conversation_id` is empty.

Then `build_blocks` does these steps:

1. It puts the records in groups. All records with the same thread key are in one group.
2. It puts each group in time sequence.
3. It finds the root of the group. The root is the record whose thread key is equal to its own id.
4. If the group has no such record, the method uses the first record of the group.
5. It makes a `DraftBlock` with this root and with the other records of the group.
6. It puts all the blocks in sequence by the time of the root.

Step 4 is necessary when the first post of the thread is not in the result.
This occurs when that post is outside the window, or hidden, or removed by the user.

## Step 6 — the sections

`add_blocks` reads the field `section` of the root post.
`Newsletter::SectionTaxonomy.for` changes this value into a newsletter section key.
For example, the values `code` and `post` both give the section `code_and_ruby`.

The method then adds the block to the list of that section.
If the Hash does not have that section key, the method does not add the block.
Only the section of the root post has an effect.
The other posts of the thread go into the same section as the root.

## The sequence of the two platforms

`call` adds the Bluesky blocks first, and the Twitter blocks after.
Thus in each section the Bluesky blocks are before the Twitter blocks.
In one platform, the blocks are in time sequence.

## Points to remember

- The class does one database read for Bluesky and one for Twitter.
- The class reads the related data with the same query, to keep the number of queries low.
- The class does not write data.
- The user controls the content of the draft with the `hidden` field and with the exclusion records.
- The thread logic and the section logic use the root post only.
