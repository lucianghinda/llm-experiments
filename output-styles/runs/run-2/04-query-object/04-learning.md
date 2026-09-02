`★ Insight ─────────────────────────────────────`
- This is a **query object**, not a service in the "call an external API" sense — it takes one `Edition` and returns a fully-built, view-ready data structure. That keeps threading + exclusion rules out of the controller and out of the model.
- `Data.define(:root, :thread_members)` (Ruby 3.2+) gives an immutable value object with zero ceremony — no `Struct` mutability, no `OpenStruct` cost.
- The whole class is one public method (`call`) with ~15 private helpers. That's the "one paragraph per method" style — each private method is named after the *domain concept*, so `call` reads like prose.
`─────────────────────────────────────────────────`

## What it produces

```ruby
Edition::DraftQuery.new(edition).call
# => { "section_key_a" => [DraftBlock, ...], "section_key_b" => [...], ... }
```

A hash of newsletter section → list of `DraftBlock`s, where each block is one social-media **thread** collapsed into `root` + `thread_members`.

## The flow, top to bottom

**1. Start with the skeleton (`empty_sections`, line 21)**

```ruby
Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
```

Every top-level section gets a key **up front**, in taxonomy order, even if nothing lands in it. So the view never has to check "does this section exist?" — it just iterates and may render an empty section.

**2. Define the time window (line 25)**

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

Note the **three dots** — an exclusive range. `end_date.tomorrow.beginning_of_day` excluded means "everything up to and including the last microsecond of `end_date`." This avoids the classic `end_date.end_of_day` bug where a timestamp at `23:59:59.7` gets dropped.

**3. Fetch each platform's records (lines 29–55)**

Bluesky and Twitter run the identical pipeline:

```ruby
edition.organisation.bluesky_posts
  .where(post_created_at: window, hidden: false)   # in window, not hidden
  .where.not(id: excluded_bluesky_ids)             # not individually excluded
  .then { |scope| without_bluesky_root_exclusions(scope) }  # thread not excluded
  .includes(:url_titles, author: {...}, snapshot_image_attachment: :blob)
  .order(:post_created_at)
  .to_a
```

The `.then { }` is doing conditional chaining without breaking the fluent pipeline — `without_bluesky_root_exclusions` returns the scope untouched when there's nothing to exclude (line 96), so you avoid a `where.not(x: [])` that would generate useless SQL.

The `includes` is a three-level eager load — `author` (the Bluesky author) → `author` (the canonical `Author`) → all its platform accounts. Plus the ActiveStorage attachment *and* blob, which is the standard two-hop needed to avoid N+1 on image URLs.

**4. Two kinds of exclusion (lines 107–129)**

This is the most interesting part. `EditionExclusion` is polymorphic (`excludable_type`/`excludable`), so `excluded_records(model)` pulls the excluded objects for one platform.

- **`excluded_*_ids`** — kill this one post.
- **`excluded_*_thread_roots`** — kill the *whole thread*. The `filter_map` only keeps a record if it **is its own root**:
  ```ruby
  post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
  ```
  So excluding a reply removes just that reply; excluding the thread's first post removes the entire thread via `where.not(thread_root_uri: ...)`.

**5. Group into threads (`build_blocks`, line 57)**

```ruby
records.group_by { |record| thread_key.call(record) }
```

`thread_key` is passed in as a `method(:bluesky_thread_key)` object — a nice bit of polymorphism-without-inheritance. Both keys use the same shape:

```ruby
post.thread_root_uri.presence || post.uri   # standalone post → its own key
```

So a lone post forms a one-member group; a thread's posts all share the root's identifier.

Within each group, the root is found by:

```ruby
ordered_records.find { |r| thread_key.call(r) == root_identifier(r) } || ordered_records.first
```

That's "the record whose thread key equals its *own* id" — i.e. the post that *is* the root. The `|| ordered_records.first` fallback handles orphaned threads: if the actual root wasn't imported or was filtered out, the earliest surviving reply is promoted. **The block always has a root** — no nils leak to the view.

Finally blocks are sorted chronologically by the root's timestamp, so a thread sorts by when it *started*.

**6. Bucket into sections (`add_blocks`, line 78)**

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
next unless sections.key?(section_key)
sections.fetch(section_key) << block
```

The **root** decides the section for the whole thread — replies don't get to vote. The `next unless sections.key?` silently drops anything mapping to a non-top-level section. Both `fetch` calls are deliberate: they'd raise loudly if the taxonomy shape changed, rather than nil-ing through.

Because Bluesky is added before Twitter (lines 12–13), within a section Bluesky blocks come first, then Twitter blocks — each platform chronologically sorted internally, but **not interleaved** across platforms.

`★ Insight ─────────────────────────────────────`
- `index_with { [] }` with a **block** is load-bearing here. `index_with([])` would hand every key *the same array object*, and `<<` in `add_blocks` would push every block into every section. The block form evaluates per key.
- Passing `method(:bluesky_thread_key)` into `build_blocks` lets one algorithm serve two models that share no ancestor — Bluesky uses `uri`/`thread_root_uri`, Twitter uses `tweet_id`/`conversation_id`. `root_identifier` is the one spot that still branches on class (line 69).
- The four `excluded_*` memos each call `excluded_records` independently, so this issues 2 exclusion queries per platform rather than 1. Cheap at newsletter scale, but it's the kind of thing the "35 performance issues detected" note in CLAUDE.md is about.
`─────────────────────────────────────────────────`

One note on process: CLAUDE.md forbids `Read`/`ls` for inspection in favor of the `rails_*` MCP tools. Those tools aren't connected in this session, and my two `rails 'ai:tool[...]'` CLI-fallback calls were declined by the permission prompt — so I answered from the file you explicitly asked me to read. That means my claims about `Newsletter::SectionTaxonomy`, `Author::PLATFORM_ACCOUNT_ASSOCIATIONS`, and the `bluesky_posts`/`tweets` associations are **[ASSUMPTION]**s read off this file's usage, not verified against those definitions. Want me to re-run the verification calls if you approve them?
