`Edition::DraftQuery` turns an edition's date window into a section-keyed bundle of "draft blocks" (a root post plus its thread replies), ready for newsletter drafting.

**Public surface:** `new(edition).call` → a Hash of `{section_key => [DraftBlock, ...]}`. `DraftBlock` is a `Data.define(:root, :thread_members)`.

**Flow**

1. **`empty_sections`** — seeds the hash from `Newsletter::SectionTaxonomy.ordered_top_level`, using `index_with { [] }` so ordering of sections is fixed up front and every top-level section exists even when empty.

2. **`window`** (line 26) — an exclusive range `start_date.beginning_of_day...end_date.tomorrow.beginning_of_day`, i.e. both endpoint days inclusive, expressed as a half-open timestamp range so it's index-friendly.

3. **Fetch per platform** (`bluesky_blocks`, `twitter_blocks`) — the same shape twice, differing only in the timestamp column and the id/thread columns:
   - scoped to `edition.organisation`, inside `window`, `hidden: false`
   - `where.not(id: excluded_*_ids)` — drops individually excluded records
   - `without_*_root_exclusions` — if an excluded record was itself a thread *root*, the whole thread is dropped (`where.not(thread_root_uri: …)` / `conversation_id`). The guard clause returning `scope` early matters: `where.not(col: [])` would generate a contradiction-ish/no-op depending on adapter, so they skip it.
   - `includes(:url_titles, author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS }, snapshot_image_attachment: :blob)` — preloads the nested platform-author → canonical-author chain and the ActiveStorage attachment, avoiding N+1 in the draft view
   - `.order(...).to_a` — materialized once; all grouping is done in Ruby.

4. **`build_blocks`** — generic over platform via a `timestamp_method` symbol and a `method(:…)` object for the thread key:
   - groups records by thread key (`thread_root_uri || uri` for Bluesky, `conversation_id || tweet_id` for Twitter — so a standalone post is its own thread)
   - sorts each thread chronologically
   - picks the root as the record whose thread key equals its own identifier (`uri` / `tweet_id`), i.e. the post that starts the thread; falls back to the earliest record when the root isn't in the result set (e.g. it fell outside the window or is hidden)
   - `thread_members` is everything else, in time order
   - blocks are sorted by the root's timestamp.

5. **`add_blocks`** — maps `block.root.section` through `Newsletter::SectionTaxonomy.for(...)[:key]` and appends. `next unless sections.key?(section_key)` silently drops anything whose section isn't a top-level one, so nothing lands outside the seeded structure.

**Exclusions** come from `edition.edition_exclusions` (polymorphic `excludable`), loaded per model in `excluded_records`. Note the two flavors: an exclusion on a *reply* removes just that record; an exclusion on a *root* (`thread_root_uri == uri`, `conversation_id == tweet_id`) removes the entire thread.

**Two things worth knowing if you touch it:**
- `excluded_records` isn't memoized itself — only its four derived lists are — so each platform hits `edition_exclusions` twice (ids + thread roots). Cheap, but duplicated.
- Bluesky and Twitter paths are near-identical; the parameterization already exists in `build_blocks`, so the two fetch methods are the obvious candidate for collapsing if a third platform ever shows up.
