`Edition::DraftQuery` collects the social posts for one newsletter edition, groups them into threads, and sorts them into newsletter sections.

## The public interface

```ruby
Edition::DraftQuery.new(edition).call
```

`call` gives back a Hash. The keys are the top-level section keys. Each value is an Array of `DraftBlock` structs.

`DraftBlock` (line 4) is a `Data` class with two fields:
- `root` — the first post of a thread.
- `thread_members` — the other posts of the same thread, in time order.

## The steps

**1. Make empty sections** (line 21)
`Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }` makes a Hash with one empty Array for each section. The taxonomy controls the order of the keys, so the output keeps the newsletter order.

**2. Calculate the time window** (line 25)
The window is an exclusive Range: from the start of `start_date` to the start of the day after `end_date`. This includes all of the last day, but it does not include the next day.

**3. Get the posts** (lines 29–55)
The two methods `bluesky_blocks` and `twitter_blocks` are parallel. Each one:
- Reads from the organisation of the edition (`bluesky_posts` / `tweets`).
- Keeps only records in the window that are not `hidden`.
- Removes the records that the editor excluded (`where.not(id: ...)`).
- Removes full threads whose root is excluded (lines 95–105).
- Preloads `url_titles`, the author chain, and the snapshot image, to prevent N+1 queries.
- Sorts by the platform timestamp column.

**4. Group into threads** (line 57, `build_blocks`)
This method is shared by both platforms. The caller gives it the timestamp method and a thread-key function, so one method serves the two different column names.
- `group_by` the thread key puts all posts of one thread together.
- In each group, the code looks for the post whose thread key is equal to its own identifier (line 60). That post is the root: for a root post, `thread_root_uri == uri` (or `conversation_id == tweet_id`).
- If no such post is found — for example, if the root is outside the window — the oldest post becomes the root.
- The other posts become `thread_members`.
- The blocks are then sorted by the timestamp of the root.

**5. Put the blocks in sections** (line 78, `add_blocks`)
For each block, the section of the root post is mapped through `Newsletter::SectionTaxonomy.for(...)` to a key. If that key is not a top-level section, the block is dropped (`next unless sections.key?`). Only the root controls the section; the replies follow their root.

## The exclusion logic (lines 107–129)

`edition_exclusions` is a polymorphic join. The class reads it two ways:
- **Single-record exclusion** — the ids go into `where.not(id: ...)`. Only that post disappears.
- **Thread exclusion** — if an excluded record is itself a thread root, its thread key goes into `where.not(thread_root_uri: ...)`. The whole thread disappears.

So excluding a reply removes one post; excluding a root removes the complete thread.

## Two observations

- `excluded_records` (line 127) is not memoized. The memoization is on the four caller methods. Each platform therefore runs the same exclusion query twice — once for the ids, once for the thread roots. Two extra queries, not a defect.
- Thread grouping happens in Ruby, after `to_a`. This is necessary, because the root detection compares two columns per row, but it does mean the full window of posts is loaded into memory.

I did not open `Newsletter::SectionTaxonomy`, `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`, or the two post models, so my statements about them come from how this file uses them.
