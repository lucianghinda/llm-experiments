No MCP tool fits "explain this specific file," so I read it directly.

`Edition::DraftQuery` is a query object that assembles the raw content of a newsletter edition: it returns a hash of `section_key => [DraftBlock, ...]`, where each block is one social-media thread.

**Entry point**

`call` builds an ordered hash with one empty array per top-level section from `Newsletter::SectionTaxonomy.ordered_top_level` (`index_with { [] }`), then appends Bluesky blocks, then Twitter blocks.

**Time window** (`window`, line 26)

`start_date.beginning_of_day...end_date.tomorrow.beginning_of_day` — a half-open range so the whole of `end_date` is included without an off-by-one on the boundary.

**Fetching** (`bluesky_blocks` / `twitter_blocks`)

Same shape for both platforms: org's posts in the window, `hidden: false`, minus explicitly excluded IDs, minus threads whose root was excluded, eager-loading `url_titles`, the author chain (`author.author` + `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`) and the snapshot image attachment/blob, ordered by creation timestamp, materialized with `to_a`.

**Thread grouping** (`build_blocks`, lines 57–67)

The only real algorithm here:
1. Group records by thread key — `thread_root_uri || uri` for Bluesky, `conversation_id || tweet_id` for Twitter. A standalone post is its own thread of one.
2. Sort each group by timestamp.
3. Pick the root: the record whose *own* identifier equals the thread key (i.e. it genuinely is the thread root, line 60-62); fall back to the earliest record when the root itself isn't in the result set (e.g. it was outside the window).
4. `DraftBlock.new(root:, thread_members: ordered_records - [root])` — a `Data` class, so blocks are immutable value objects.
5. Sort blocks by their root's timestamp.

**Section assignment** (`add_blocks`, lines 78–85)

Each block inherits its section from `block.root.section`, normalized through `SectionTaxonomy.for(...).fetch(:key)`. Blocks whose key isn't a top-level section are silently dropped (`next unless sections.key?`).

**Exclusions** (lines 107–129)

`edition.edition_exclusions` is polymorphic (`excludable_type`/`excludable`). Two effects per platform:
- `excluded_*_ids` — drop those individual records.
- `excluded_*_thread_roots` — if an excluded record *is* a thread root (`thread_root_uri == uri`, `conversation_id == tweet_id`), the entire thread is dropped via `where.not(thread_root_uri: ...)`. The `without_*_root_exclusions` guards skip the `where.not` when the list is empty, since `where.not(col: [])` would be a no-op that still bloats the SQL.

All of these are memoized with the project's leading-underscore ivar convention.

**Two behavioral notes**

- Bluesky and Twitter blocks are appended sequentially, so within a section all Bluesky blocks precede all Twitter blocks — they aren't merged into one chronological stream. Each platform's blocks are internally sorted by time.
- `excluded_records(model)` runs a fresh query per call; since `excluded_bluesky_ids` and `excluded_bluesky_thread_roots` memoize independently, that's 4 exclusion queries total (2 per platform) rather than 2.
