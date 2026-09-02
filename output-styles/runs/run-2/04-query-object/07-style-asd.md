I used `Read` because you asked for that file directly. The `rails_*` MCP tools are not connected in this session.

## What the class does

`Edition::DraftQuery` collects the social posts for one edition. It groups the posts into threads. Then it puts each thread into a newsletter section.

The result is a Hash. Each key is a section key. Each value is an Array of `DraftBlock`.

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A block has one root post and the other posts of the same thread.

## The steps

**1. Make the empty sections** (`app/services/edition/draft_query.rb:21`)

`Newsletter::SectionTaxonomy.ordered_top_level` gives the section keys. `index_with { [] }` gives each key an empty Array. The order of the sections comes from the taxonomy, not from the posts.

**2. Calculate the time window** (line 25)

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

This is an exclusive Range. It starts at 00:00 of the start date. It stops at 00:00 of the day after the end date. Thus the full end date stays in the window.

**3. Get the records** (lines 29–55)

The two methods `bluesky_blocks` and `twitter_blocks` are the same, but they use different columns:

| Bluesky | Twitter |
|---|---|
| `post_created_at` | `tweet_created_at` |
| `uri` | `tweet_id` |
| `thread_root_uri` | `conversation_id` |

Each query does this:
- Selects the posts of the organisation in the window.
- Removes the hidden posts.
- Removes the posts that the exclusions name.
- Removes the posts whose thread root is excluded.
- Preloads `url_titles`, the author chain and the snapshot image. This prevents N+1 queries.
- Sorts by the creation time and loads the records into memory.

**4. Build the blocks** (line 57)

The method groups the records by the thread key. The thread key is `thread_root_uri` (or `conversation_id`). If that value is empty, the record is its own key.

In each group, the code finds the root. The root is the record whose thread key is equal to its own identifier. If no record agrees, the code uses the first record in time. The other records become `thread_members`.

Last, the blocks get a sort by the time of the root. Thus a thread keeps the position of its first post.

**5. Put the blocks into the sections** (line 78)

For each block, `Newsletter::SectionTaxonomy.for(block.root.section)` gives the section key. If the empty sections Hash does not have that key, the code ignores the block. This removes the posts of a sub-section or of an unknown section.

Note that `call` adds the Bluesky blocks before the Twitter blocks. In one section, all Bluesky blocks come first. The two platforms do not mix by time.

## The exclusions

`edition.edition_exclusions` is a polymorphic association. The class uses the exclusions on two levels:

- **Record level** — `excluded_bluesky_ids` / `excluded_twitter_ids` remove one post.
- **Thread level** — `excluded_bluesky_thread_roots` / `excluded_twitter_thread_roots` keep only the excluded posts that are the root of their thread. The query then removes all replies of those threads.

Thus, if you exclude the root of a thread, the full thread goes away. If you exclude a reply, only that reply goes away.

## Two small points

- `excluded_records` (line 127) has no memoization. The four memoized methods call it, so the database gets four queries in place of two. A memoized Hash by model name would remove the two extra queries.
- `root_identifier` (line 69) gives `nil` for a different class. In that condition, no record can be the root, and the code uses the first record in time. That is a safe result, but it is silent.

[ASSUMPTION] I did not open `Newsletter::SectionTaxonomy` or `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`. My description of them comes from the calls in this file only.
