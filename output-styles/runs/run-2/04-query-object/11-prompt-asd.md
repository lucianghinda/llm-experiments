No MCP tool fits this request — you asked for that specific file directly, so I read it with `Read` and did not edit it.

Below is the explanation. It follows ASD-STE100: simple present tense, active voice, short sentences, one idea per sentence, and the same word for the same thing.

---

## 1. Purpose

The class `Edition::DraftQuery` makes the draft content of one edition. It reads the Bluesky posts and the tweets of the organisation of that edition. It puts them into the sections of the newsletter.

## 2. How to use the class

Give one edition to `new`. Then call `call`. `call` gives back a Hash. Each key of the Hash is a top-level section. Each value is a list of blocks.

## 3. The block

A block is a `Data` object with the name `DraftBlock`. A block has two parts:

- `root` — the first record of a thread.
- `thread_members` — the other records of the same thread, in time order.

## 4. Step 1 — make the empty sections

`empty_sections` reads the top-level sections from `Newsletter::SectionTaxonomy.ordered_top_level`. It makes one empty list for each section. The sections keep the order of the taxonomy.

## 5. Step 2 — calculate the time window

`window` makes a range of time. The range starts at 00:00 on the start date of the edition. The range stops before 00:00 on the day after the end date. The range is exclusive at the end (`...`). Thus the range contains the full last day, but no part of the next day.

## 6. Step 3 — read the records

`bluesky_blocks` and `twitter_blocks` do the same operations on two different models. For each model, the code:

- selects only the records in the time window;
- selects only the records with `hidden` equal to false;
- removes the records that the edition excludes;
- removes the records of an excluded thread root;
- loads the related data in the same query (`url_titles`, the author accounts, the snapshot image and its blob);
- puts the records in time order;
- sends the records to `build_blocks`.

The two methods use different columns. Posts use `post_created_at`. Tweets use `tweet_created_at`.

## 7. Step 4 — the exclusions

`excluded_records` reads the `edition_exclusions` of the edition for one model. It gives back the excluded records. Two groups of values come from these records:

- `excluded_bluesky_ids` and `excluded_twitter_ids` give the ids. The query removes these records.
- `excluded_bluesky_thread_roots` and `excluded_twitter_thread_roots` give the identifiers of the excluded records that are thread roots. A record is a thread root when its thread identifier is equal to its own identifier. The query removes all the records of these threads.

The result is this rule:

- If you exclude the first record of a thread, the code removes the full thread.
- If you exclude a record in the middle of a thread, the code removes only that record.

`without_bluesky_root_exclusions` and `without_twitter_root_exclusions` add the second condition only when the list of thread roots is not empty. This prevents a `NOT IN ()` condition with no values.

## 8. Step 5 — make the blocks

`build_blocks` puts the records in groups. The key of a group is the thread key:

- For a post, the thread key is `thread_root_uri`. If this value is empty, the key is `uri`.
- For a tweet, the thread key is `conversation_id`. If this value is empty, the key is `tweet_id`.

For each group, the code does these operations:

1. It puts the records of the group in time order.
2. It finds the root. The root is the record whose own identifier (`uri` for a post, `tweet_id` for a tweet) is equal to the thread key.
3. If no record agrees with this condition, the first record in time becomes the root. This occurs when the edition window does not contain the first record of the thread.
4. It makes a `DraftBlock`. The block has this root and all the other records of the group.

At the end, `build_blocks` puts the blocks in the order of the time of their roots.

## 9. Step 6 — put the blocks in the sections

`add_blocks` reads the section of the root record. `Newsletter::SectionTaxonomy.for` changes this value into a key. Then:

- If the Hash of sections does not have this key, the code discards the block.
- If the Hash has the key, the code adds the block to the end of the list of that section.

`call` adds the Bluesky blocks first. Then it adds the Twitter blocks. Thus, in one section, all the Bluesky blocks come before all the Twitter blocks. In each of these two parts, the blocks stay in time order.

## 10. Notes

- The code discards a block when its section key is not a top-level key. It gives no message and no error. A record with a sub-section value can disappear from the draft.
- `excluded_records` makes a new database query for each call. The code calls it two times for each model: one time for the ids, and one time for the thread roots. This makes four queries. A memo variable on `excluded_records` decreases this number to two.
- The blocks are not in one single time order in a section. The platform (Bluesky or Twitter) has the first priority. The time has the second priority.
