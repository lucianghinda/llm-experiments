I used `Read` here because you named the file directly. Note: the project's MCP `rails_*` tools are not connected in this session, and the CLI fallback (`bin/rails 'ai:tool[schema]'`) needs approval that I do not have. So one point below is marked as an assumption.

# `Edition::DraftQuery` — description in Simplified Technical English

## 1. Purpose

The class makes the draft content for one newsletter edition. It reads the social posts of the organisation. It puts these posts into newsletter sections. It gives the result to the caller.

## 2. Input and output

The class takes one `edition` object. The `call` method gives back a Hash.

- Each key of the Hash is a top-level section key. `Newsletter::SectionTaxonomy.ordered_top_level` gives these keys in the correct sequence.
- Each value is an Array of `DraftBlock` items.

A `DraftBlock` is a small data object with two fields:

- `root` — the first post of a thread.
- `thread_members` — the other posts of the same thread, in time sequence.

Sections that have no content stay in the Hash as empty Arrays.

## 3. The time window

The `window` method makes an exclusive range. The range starts at the first moment of `edition.start_date`. The range stops at the first moment of the day after `edition.end_date`. Thus the range contains the full end date.

## 4. The steps

The `call` method does these steps:

1. Make one empty Array for each top-level section.
2. Get the Bluesky blocks. Add them to the sections.
3. Get the Twitter blocks. Add them to the sections.
4. Give the Hash to the caller.

## 5. How the class finds the posts

`bluesky_blocks` and `twitter_blocks` use the same procedure. Only the model, the timestamp column, and the thread key are different.

The database query keeps a post only if all of these conditions are true:

- The post is related to the organisation of the edition.
- The time of the post is in the window.
- The `hidden` flag of the post is false.
- The edition does not exclude the post.
- The edition does not exclude the thread root of the post.

The query also loads the related records in advance: the URL titles, the author with the platform accounts, and the snapshot image with its blob. This prevents many small database queries.

## 6. How the class makes the threads

The `build_blocks` method does these steps:

1. Group the posts by their thread key. For Bluesky, the key is `thread_root_uri`, or `uri` if `thread_root_uri` is empty. For Twitter, the key is `conversation_id`, or `tweet_id` if `conversation_id` is empty.
2. Sort the posts of each group by time.
3. Find the root. The root is the post whose identifier is equal to the thread key. If no post agrees with this rule, use the oldest post of the group.
4. Make a `DraftBlock`. Put the other posts into `thread_members`.
5. Sort all the blocks by the time of their root.

A post that has no thread becomes a block with one root and no thread members.

## 7. How the class puts the blocks into sections

The `add_blocks` method reads the `section` value of the root post. `Newsletter::SectionTaxonomy.for` changes this value into a section key. If the Hash contains this key, the method adds the block to that Array. If the Hash does not contain this key, the method ignores the block. Thus the section of the root controls the full thread. The sections of the other posts of the thread have no effect.

## 8. How the exclusions operate

`excluded_records` reads the `edition_exclusions` records of the edition for one model. The class uses these records in two ways:

- **Single posts.** `excluded_bluesky_ids` and `excluded_twitter_ids` give all excluded IDs. The query removes these posts.
- **Full threads.** `excluded_bluesky_thread_roots` and `excluded_twitter_thread_roots` keep only the excluded posts that are their own thread root. The query then removes all posts that have one of these thread roots. Thus one exclusion removes the full thread.

The class stores these lists in memoized variables. Therefore the database queries occur one time only.

## 9. One possible problem

`[ASSUMPTION]` I could not verify the nullability of the `thread_root_uri` and `conversation_id` columns, because the schema tools are not available in this session.

If these columns permit NULL, `without_bluesky_root_exclusions` and `without_twitter_root_exclusions` can remove too much. SQL gives an unknown result when it compares NULL with `NOT IN`. Then the database removes the row. Thus a single post that has no thread root disappears from the draft, but only when the edition excludes minimum one thread root.

A safe form of the condition is:

```ruby
scope.where(thread_root_uri: nil).or(scope.where.not(thread_root_uri: excluded_bluesky_thread_roots))
```

Tell me if you want me to confirm the column definitions and make this change.
