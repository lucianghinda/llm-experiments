I read the file directly because you asked for that file. The project rules prefer the `rails_*` MCP tools, but no MCP tool shows the full source of one service object.

## Purpose

`Edition::DraftQuery` collects the social posts for one newsletter edition. It groups the posts into threads. Then it puts each thread into a newsletter section.

## Result shape

`DraftBlock` (`draft_query.rb:4`) is a value object. It holds a `root` record and the other `thread_members`.

`call` (`draft_query.rb:10`) returns a Hash. The keys are the top-level section keys. Each value is an array of `DraftBlock` objects.

## Steps

**1. Make the empty sections.** `empty_sections` asks `Newsletter::SectionTaxonomy.ordered_top_level` for the section keys. It gives each key an empty array. The order of the taxonomy controls the order of the sections.

**2. Calculate the time window.** `window` (`draft_query.rb:25`) makes an exclusive range. The range starts at the first second of `start_date`. It stops before the first second of the day after `end_date`. Thus the last day is fully included.

**3. Read the posts.** `bluesky_blocks` and `twitter_blocks` do the same operations for two platforms:
- Start from the posts of the edition organisation.
- Keep the records in the window that are not `hidden`.
- Remove the records that the user excluded.
- Preload `url_titles`, the author accounts and the snapshot image. This prevents N+1 queries.
- Sort by the creation time.

**4. Group the posts into threads.** `build_blocks` (`draft_query.rb:57`) groups the records with a thread key. For Bluesky the key is `thread_root_uri`, or the post `uri` if there is no root. For Twitter the key is `conversation_id`, or the `tweet_id`. The code then sorts each group by time. It selects as `root` the record whose own identifier is equal to the thread key. If that record is absent, the code uses the first record. The other records become `thread_members`. At the end the code sorts the blocks by the time of the root.

**5. Put the blocks into sections.** `add_blocks` (`draft_query.rb:78`) reads `block.root.section`. It converts that value to a taxonomy key. If the key is not a top-level key, the code ignores the block. Only the section of the root is important. The replies follow their root.

## Exclusions

`EditionExclusion` records hold the manual exclusions of the edition. The code uses them in two ways:

- `excluded_bluesky_ids` and `excluded_twitter_ids` remove one single record.
- `excluded_bluesky_thread_roots` and `excluded_twitter_thread_roots` keep only the excluded records that are thread roots. `without_bluesky_root_exclusions` and `without_twitter_root_exclusions` then remove the full thread.

Thus, if you exclude a reply, you lose only that reply. If you exclude the first post of a thread, you lose the complete thread.

## One observation

`excluded_records` (`draft_query.rb:127`) has no memoization. The four exclusion methods call it four times. This makes four queries in place of one. The four public methods are memoized, so each query occurs one time only. This is a small cost, but you can decrease it with a memoized `excluded_records` per model.
