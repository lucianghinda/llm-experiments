The rails MCP tools are not connected in this session, and you asked directly for a file read — so I read `app/services/edition/draft_query.rb` with `Read`.

## What the class does

`Edition::DraftQuery` collects the social posts for one newsletter edition. It groups the posts into threads, and it puts each thread into a newsletter section. The result is the draft content of the edition.

## The data structure

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A `DraftBlock` is one thread. The `root` is the first post. The `thread_members` are the replies, in time sequence.

## The primary flow (`call`, lines 10–15)

1. `empty_sections` makes a hash. The keys are the top-level section keys from `Newsletter::SectionTaxonomy`. Each value is an empty array.
2. `add_blocks` puts the Bluesky blocks into the hash.
3. `add_blocks` then puts the Twitter blocks into the hash.

The method returns the hash. Thus the sequence of the sections comes from the taxonomy, not from the posts.

## The time window (lines 25–27)

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

This is a half-open range. It starts at midnight on the start date. It stops before midnight on the day after the end date. Thus the full end date is in the window.

## The two queries (lines 29–55)

`bluesky_blocks` and `twitter_blocks` have the same structure. Only the column names and the model change. Each query does this:

- It gets the posts of the organisation of the edition.
- It keeps only the posts in the window, and only the posts that are not hidden.
- It removes the posts that the edition excludes (`where.not(id: excluded_…_ids)`).
- It removes the posts whose thread root is excluded (lines 95–105).
- It preloads `url_titles`, the author with the platform accounts, and the snapshot image with its blob. This prevents N+1 queries in the view.
- It sorts by the creation time, and makes an array.

Each query then calls `build_blocks` with three items: the records, the name of the timestamp method, and a `Method` object for the thread key.

## How the threads are made (`build_blocks`, lines 57–67)

1. The method groups the records by their thread key. For Bluesky the key is `thread_root_uri`, or the `uri` of the post if `thread_root_uri` is empty (line 88). For Twitter the key is `conversation_id`, or the `tweet_id` (line 92).
2. The method sorts each group by time.
3. The method finds the root. The root is the record whose thread key is equal to its own identifier (`uri` or `tweet_id`, lines 69–76). This is the first post of the thread. If the root is not in the group, the method uses the earliest record.
4. The method makes a `DraftBlock`. The other records become the `thread_members`.
5. The method sorts all the blocks by the time of their root.

## How the blocks go into sections (`add_blocks`, lines 78–85)

For each block, the method reads `block.root.section`. It sends this value to `Newsletter::SectionTaxonomy.for`, and it takes the `:key`. If the hash has this key, the method adds the block. If the hash does not have this key, the method ignores the block. Thus a sub-section or an unknown section does not stop the process, but its content does not go into the draft.

## The exclusions (lines 107–129)

`edition.edition_exclusions` is a polymorphic association. It can point to a Bluesky post or to a tweet. The class uses the exclusions in two ways:

- **Single post** — `excluded_bluesky_ids` and `excluded_twitter_ids` give the ids. The query removes these posts only.
- **Full thread** — `excluded_bluesky_thread_roots` and `excluded_twitter_thread_roots` keep only the excluded records that are their own thread root. The query then removes all the posts of these threads. Thus, if you exclude the first post of a thread, you exclude the full thread. If you exclude a reply, you exclude that reply only.

All four methods are memoized with a leading-underscore variable.

## Two points to note

- `excluded_records` runs a database query on each call, and the memoization is on the four result lists, not on this method. Thus the class makes two queries for Bluesky and two for Twitter, and each pair reads the same rows.
- Inside one section, all the Bluesky blocks come before all the Twitter blocks. `build_blocks` sorts by time, but only inside one platform. `call` adds Bluesky first (line 12). The two platforms are not merged by time.
