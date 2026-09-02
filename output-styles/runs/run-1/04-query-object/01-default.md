I read the file directly since you asked me to open that specific path. I could not verify the collaborators (`Newsletter::SectionTaxonomy`, `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`, the `bluesky_posts`/`tweets` associations) — the `rails ai:tool` CLI fallback wasn't approved, so anything I say about their internals below is marked `[ASSUMPTION]`.

## What it does

`Edition::DraftQuery` takes an `Edition` and returns the raw material for a newsletter draft: a hash of newsletter sections → lists of "blocks", where a block is one social post plus the rest of its thread.

## The shape of the result

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

`call` (line 10) builds `empty_sections` — one empty array per top-level section, keyed and *ordered* by `Newsletter::SectionTaxonomy.ordered_top_level` — then pours Bluesky blocks and Twitter blocks into it. `index_with { [] }` gives each key a fresh array. Because Ruby hashes preserve insertion order, the taxonomy's order becomes the section order in the output.

## 1. Fetching candidates

`bluesky_blocks` (29) and `twitter_blocks` (43) are the same pipeline over two different tables:

- **Date window** — `window` (25) is a half-open range: `start_date.beginning_of_day...end_date.tomorrow.beginning_of_day`. Using `tomorrow.beginning_of_day` with `...` includes all of the end date without the microsecond-precision problems of `end_of_day`.
- **Filters** — scoped to the edition's organisation, inside the window, `hidden: false`, and not in the exclusion sets (below).
- **Eager loading** — `url_titles`, the author chain (`author: { author: PLATFORM_ACCOUNT_ASSOCIATIONS }` — the platform account and the underlying canonical `Author` with all its linked platform accounts), and the snapshot image attachment + blob. This is preloading everything the draft renderer will touch, to avoid N+1s.
- `.to_a` — deliberately materializes, because all the grouping that follows happens in Ruby, not SQL.

## 2. Exclusions (the subtle part)

An edition has `edition_exclusions` (polymorphic `excludable`). `excluded_records` (127) loads the excluded records for a given model. Two different exclusion semantics are derived from it:

- `excluded_bluesky_ids` / `excluded_twitter_ids` (107, 117) — exclude *that one post*.
- `excluded_bluesky_thread_roots` / `excluded_twitter_thread_roots` (111, 121) — if the excluded record **is itself a thread root** (`thread_root_uri == uri`, or `conversation_id == tweet_id`), then the whole thread is dropped via `where.not(thread_root_uri: ...)` / `where.not(conversation_id: ...)`.

So excluding a reply removes just the reply; excluding a thread's first post removes the entire thread. The `without_*_root_exclusions` helpers (95, 101) guard against `where.not(col: [])`, which would otherwise produce a condition that filters out everything with a `NULL`-ish result — they return the scope untouched when there's nothing to exclude. All four exclusion methods are memoized with the leading-underscore ivar convention.

## 3. Grouping into threads

`build_blocks` (57) is shared between both platforms; the platform-specific bits are passed in as a timestamp method name and a `thread_key` callable (`method(:bluesky_thread_key)` / `method(:twitter_thread_key)`).

- `bluesky_thread_key` (87) → `thread_root_uri` if present, else the post's own `uri`. `twitter_thread_key` (91) → `conversation_id` else `tweet_id`. A standalone post is therefore its own thread of one.
- Records are `group_by`'d on that key, each group sorted chronologically.
- The **root** is the member whose thread key equals its own identifier (`root_identifier`, 69 — `uri` for Bluesky, `tweet_id` for Twitter), i.e. the genuine first post. If the actual root isn't in the result set (hidden, excluded, or outside the window), it falls back to `ordered_records.first` — the earliest surviving reply is promoted to root.
- `thread_members` is everything else: `ordered_records - [root]`.
- Finally blocks are sorted by their root's timestamp, so each platform's blocks come out chronologically.

## 4. Placing blocks into sections

`add_blocks` (78) asks the taxonomy which top-level section a root's `section` value maps to and appends the block there. `next unless sections.key?(section_key)` silently drops anything whose section isn't a current top-level key — so a post carrying a stale or non-top-level section value just doesn't appear in the draft.

`[ASSUMPTION]` `SectionTaxonomy.for(x)` returns a hash containing `:key` and presumably normalizes/handles nil sections into some default; `fetch(:key)` would raise if it didn't. Worth confirming if you're chasing a bug where posts go missing from a draft.

## Notable design choices

- The section hash is keyed by taxonomy order, but **within a section, Bluesky blocks all come before Twitter blocks** — the two are appended sequentially and never merged/re-sorted by time. If you wanted a single chronological feed per section, that's the line to change.
- Per call, `excluded_records` runs one query per model *per accessor* — `excluded_bluesky_ids` and `excluded_bluesky_thread_roots` each hit the DB (the memoization is on the derived arrays, not on `excluded_records` itself), so Bluesky exclusions are loaded twice, Twitter's twice. Small and probably intentional-by-omission, but it's the one easy efficiency win here.
