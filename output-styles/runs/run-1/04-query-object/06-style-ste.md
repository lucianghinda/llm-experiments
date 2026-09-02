`rails_*` MCP tools are not connected here, and the CLI fallback (`bin/rails 'ai:tool[search_code]'`) was denied, so I could not verify the collaborator classes. Everything below comes from the file itself. Points that depend on outside code are marked `[ASSUMPTION]`.

## Purpose

`Edition::DraftQuery` builds the draft content of a newsletter edition. It takes one `Edition` and returns a hash: section key → list of content blocks, ready to render.

## Top-level flow (`app/services/edition/draft_query.rb:10`)

```ruby
empty_sections.tap do |sections|
  add_blocks(sections, bluesky_blocks)
  add_blocks(sections, twitter_blocks)
end
```

1. Create an empty hash with one entry per newsletter section.
2. Fill it with Bluesky posts.
3. Fill it with Twitter tweets.
4. `tap` returns the hash itself.

## The block value object (`:4`)

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A block is one thread: the first post (`root`) plus the replies that follow it (`thread_members`). A single post with no replies is a block with an empty `thread_members`.

## Step 1 — empty sections (`:21`)

`Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }` makes the hash. `index_with` with a **block** is important: each key gets its own new array. Passing `index_with([])` would share one array between all keys.

`[ASSUMPTION]` `ordered_top_level` returns the section keys in display order. The ordering of the result hash therefore comes from the taxonomy, not from this class.

## Step 2 — the date window (`:25`)

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

An **exclusive** range (`...`). It starts at midnight of `start_date` and stops just before midnight after `end_date`. So both the first and the last day are fully included.

## Step 3 — loading records (`:29` and `:43`)

Both platforms use the same shape:

- scope to the edition's organisation (`bluesky_posts` / `tweets`);
- keep only records inside the window and with `hidden: false`;
- drop records excluded by id;
- drop records whose whole thread was excluded (`then { ... }`);
- preload associations (`url_titles`, the author chain, the snapshot image and its blob) to avoid N+1 queries;
- order by creation time and load with `to_a`.

The only differences are the timestamp column (`post_created_at` vs `tweet_created_at`) and the thread key.

## Step 4 — grouping into threads (`:57`)

`build_blocks` is shared by both platforms. It receives the records, the timestamp method name, and a thread-key function (passed as `method(:...)`).

```ruby
records.group_by { |record| thread_key.call(record) }
```

Thread keys:
- Bluesky (`:87`): `thread_root_uri` if present, else the post's own `uri`.
- Twitter (`:91`): `conversation_id` if present, else the tweet's own `tweet_id`.

So a standalone post is its own thread.

Inside each group it picks the root:

```ruby
root = ordered_records.find { |r| thread_key.call(r) == root_identifier(r) } || ordered_records.first
```

`root_identifier` (`:69`) returns the record's **own** id (`uri` or `tweet_id`). The test therefore means: "this record points at itself as thread root." The `|| ordered_records.first` fallback handles the case where the real root is missing from the set — for example it is hidden, excluded, or outside the date window. Then the earliest available record acts as the root.

`thread_members` is `ordered_records - [root]`, still in time order. Finally blocks are sorted by their root's timestamp (`:66`).

## Step 5 — placing blocks in sections (`:78`)

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
next unless sections.key?(section_key)
```

The section comes from the **root record only**; replies do not affect placement. `fetch(:key)` will raise if the taxonomy entry has no `:key`, which is a deliberate loud failure. The `next unless` line silently skips blocks whose section is not a top-level one — for example a sub-section, or a section not present in `ordered_top_level`.

Because Twitter blocks are added after Bluesky blocks, inside one section all Bluesky blocks come before all Twitter blocks. They are **not** merged by time.

## Exclusions — two levels (`:95`–`:129`)

`edition.edition_exclusions` is a polymorphic list of things the editor removed. The class reads it twice per platform:

- **`excluded_*_ids`** (`:107`, `:117`) — drop exactly these records.
- **`excluded_*_thread_roots`** (`:111`, `:121`) — of the excluded records, keep only those that are their own thread root (`thread_root_uri == uri`, `conversation_id == tweet_id`). Their identifiers are then used to drop every other record in the same thread.

The meaning: excluding a **reply** removes just that reply; excluding a **thread root** removes the whole thread.

The `without_*_root_exclusions` guards (`:95`, `:101`) return the scope unchanged when there is nothing to exclude. This avoids generating `NOT IN ()`.

All four lists are memoized with the project's leading-underscore style (`@_excluded_...`).

## Two things worth checking

1. **`where.not` and NULL.** `scope.where.not(thread_root_uri: [...])` compiles to `thread_root_uri NOT IN (...)`. In SQL that is `NULL` for a `NULL` column, so the row does **not** match. If `thread_root_uri` is nullable — and `bluesky_thread_key` using `.presence` suggests it can be blank — then standalone posts would disappear from the draft as soon as any thread root is excluded. Same for `conversation_id` (`:104`). `[ASSUMPTION]` I could not check the schema; if those columns are `NOT NULL` with a self-reference default, there is no problem.

2. **Repeated queries.** `excluded_records` (`:127`) is not memoized itself. Each of the four memoized methods calls it, so the exclusions are queried four times per `call`. Memoizing `excluded_records` per model would cut that to two.
