I couldn't run the MCP CLI fallback (needs approval), so the explanation below is grounded in this file's own code; where it depends on collaborators (`Newsletter::SectionTaxonomy`, `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`, model columns) I mark it as `[ASSUMPTION]`.

## What it does

`Edition::DraftQuery` (`app/services/edition/draft_query.rb:3`) takes an `Edition` and returns the draft newsletter content for it: a hash of **section key → array of `DraftBlock`s**, where each block is one thread (a root post plus its replies), sorted by time.

It's a read-only query object — `new(edition).call`, no mutation.

## The pieces

**`DraftBlock = Data.define(:root, :thread_members)`** (line 4) — an immutable value object. `root` is the post that starts a thread; `thread_members` is every other post in that thread, in time order, with the root removed.

**`call`** (line 10) builds an empty skeleton and pours two platforms into it:

```ruby
empty_sections.tap do |sections|
  add_blocks(sections, bluesky_blocks)
  add_blocks(sections, twitter_blocks)
end
```

Because `empty_sections` is `SectionTaxonomy.ordered_top_level.index_with { [] }` (line 22), the returned hash **always has every top-level section as a key, in taxonomy order, even when empty** — so a view can iterate sections without nil checks. Bluesky is added before Twitter, so within a section Bluesky blocks precede Twitter ones (there's no final cross-platform re-sort). [ASSUMPTION] `ordered_top_level` returns section keys in display order.

**`window`** (line 26) is `start_date.beginning_of_day...end_date.tomorrow.beginning_of_day` — a half-open range, i.e. the whole of `end_date` is included but nothing from the following day. Using `...` with `tomorrow.beginning_of_day` avoids the classic off-by-one where `end_date.end_of_day` misses sub-second timestamps.

## Fetching (lines 29–55)

`bluesky_blocks` and `twitter_blocks` are the same shape, differing only in association, timestamp column, and thread key:

1. Scope from `edition.organisation` (so it's org-scoped, not global).
2. Filter to the date `window` and `hidden: false`.
3. `where.not(id: excluded_*_ids)` — drop individually excluded records.
4. `then { without_*_root_exclusions(scope) }` — drop entire threads whose root was excluded.
5. `includes(...)` to preload `:url_titles`, the nested author chain, and the snapshot image attachment + blob — this is the N+1 defense for rendering the draft.
6. `order` by the platform's created-at, then `to_a` so grouping happens in Ruby.

The `.then { ... }` is there because the exclusion filter is conditional — it lets a guard clause (`return scope if ... .empty?`) stay inside the chain instead of breaking it into intermediate variables.

## Thread grouping (`build_blocks`, line 57)

This is the interesting bit. Given flat records:

1. `group_by(&thread_key)` — Bluesky groups by `thread_root_uri` falling back to the post's own `uri` (line 88); Twitter by `conversation_id` falling back to `tweet_id` (line 92). The fallback means a standalone post forms a group of one.
2. Sort each group chronologically.
3. Pick the root: the record whose **own identifier equals the thread key** (`uri` for Bluesky, `tweet_id` for Twitter — `root_identifier`, line 69). If the actual root isn't in the result set — it was outside the window, hidden, or just not imported — it falls back to `ordered_records.first`, the earliest available post. So a thread never renders headless.
4. `DraftBlock.new(root:, thread_members: ordered_records - [root])`.
5. Sort blocks by the root's timestamp.

`thread_key` and `timestamp_method` are passed as `Method` objects (`method(:bluesky_thread_key)`, `&timestamp_method`), which is how one `build_blocks` serves both platforms.

## Exclusions (lines 95–129)

`edition.edition_exclusions` is polymorphic (`excludable_type` / `excludable`). The class reads it twice per platform for two different purposes:

- **`excluded_*_ids`** — remove just that record.
- **`excluded_*_thread_roots`** — `filter_map` keeps only excluded records that *are* their own thread root (`thread_root_uri == uri`, `conversation_id == tweet_id`). Those identifiers then feed `where.not(thread_root_uri: ...)`, so **excluding a thread root drops the entire thread**, while excluding a reply drops only that reply.

All four are memoized with the leading-underscore ivar convention (`@_excluded_bluesky_ids`), per this project's style rule.

## Placement (`add_blocks`, line 78)

Each block's section comes from its **root** post: `SectionTaxonomy.for(block.root.section).fetch(:key)`. `next unless sections.key?(section_key)` silently discards blocks mapping to a key that isn't a top-level section — so replies never override the thread's placement, and an unknown/sub-level section can't blow up the render. [ASSUMPTION] `SectionTaxonomy.for` returns a hash with a `:key` and handles a nil/unknown `section`; `fetch` would raise if it returned something without `:key`.

## One thing worth noting

`excluded_records` (line 127) is called four times per `call` — twice for `Bluesky::Post`, twice for `Twitter::Tweet` — and it isn't memoized itself, only its four callers are. That's 4 queries against `edition_exclusions` where 2 would do (or 1 loading all exclusions and partitioning by type). Small, but it's the only redundant work in the class if you ever want to tighten it.
