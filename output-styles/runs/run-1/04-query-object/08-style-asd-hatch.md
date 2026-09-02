No MCP tool fits this; falling back to `Read` because you asked for this specific file, and the `rails_*` MCP tools are not connected in this session.

## What it does

`Edition::DraftQuery` builds the draft content of one newsletter edition. It gives you a hash: section key → list of `DraftBlock` values. Each block is one social-media thread (a root post plus its replies).

```ruby
Edition::DraftQuery.new(edition).call
# => { "gems" => [DraftBlock, ...], "articles" => [...], ... }
```

## Step by step

**1. Empty sections (`empty_sections`, line 21)**
It starts from `Newsletter::SectionTaxonomy.ordered_top_level` and makes each key point to an empty array. This fixes the section order in the result, and keeps empty sections in the output.

**2. Time window (`window`, line 25)**
`start_date.beginning_of_day...end_date.tomorrow.beginning_of_day` — an exclusive range. It covers the full end date, but stops before the next day begins.

**3. Fetch posts (`bluesky_blocks` / `twitter_blocks`, lines 29 and 43)**
The two methods are the same shape, only the column names differ. Each one:
- takes the posts of the edition's organisation inside the window, with `hidden: false`;
- removes posts that the editor excluded by id (`excluded_*_ids`);
- removes whole threads whose root was excluded (`without_*_root_exclusions`);
- preloads url titles, the author and its platform accounts, and the snapshot image blob — this prevents N+1 queries in the view;
- orders by creation time and loads the records with `to_a`.

**4. Group into threads (`build_blocks`, line 57)**
It groups the records by thread key — `thread_root_uri` for Bluesky, `conversation_id` for Twitter, with a fallback to the record's own identifier for standalone posts. In each group it looks for the record that *is* the thread root: the one whose thread key equals its own id (`root_identifier`, line 69). If that root is not in the set (for example it is outside the window, or hidden), it uses the earliest record instead. The remaining records become `thread_members`. Blocks are then sorted by the root's timestamp.

**5. Put blocks in sections (`add_blocks`, line 78)**
The section comes from the root post only — `block.root.section` — through `SectionTaxonomy.for(...)`. If the resolved key is not a top-level section, the block is dropped silently (`next unless sections.key?`).

## Exclusion model

`edition_exclusions` is a polymorphic join. `excluded_records` (line 127) loads the excluded posts for one model. From those, the class derives two things:

- **`excluded_*_ids`** — remove that single post.
- **`excluded_*_thread_roots`** — the excluded post is itself a thread root (`thread_root_uri == uri`, or `conversation_id == tweet_id`). Then the *whole thread* goes away.

So: exclude a reply → you lose one post; exclude the root → you lose the thread.

## Two points to note

- **Order across platforms.** `call` adds Bluesky blocks first, then Twitter blocks (lines 12–13). Inside one section, all Bluesky blocks come before all Twitter blocks. Each platform is sorted by time, but the merged list is not. If you want one chronological list per section, sort after both `add_blocks` calls.
- **Duplicate queries.** `excluded_records` is not memoized; only its two derived lists are. So the exclusions query runs twice per platform (four times in total). Memoizing `excluded_records` per model would cut that to two.

[ASSUMPTION] I did not verify `Newsletter::SectionTaxonomy`, `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`, or the `bluesky_posts` / `tweets` associations on `Organisation` — my description of them comes from how this file uses them. Tell me if you want me to check any of these.
