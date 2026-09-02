Here's how `Edition::DraftQuery` works.

`★ Insight ─────────────────────────────────────`
- This is a **query object**, not a service in the "do something" sense — it takes one input (`edition`) and returns a data structure. The `initialize`/`call` pair with everything else private is the canonical shape for that pattern.
- `Data.define(:root, :thread_members)` (Ruby 3.2+) gives an immutable value object with no behavior — cheaper and safer than a `Struct`, and it signals "this is a transport shape for the view layer," not a model.
- The whole class is really *one* pipeline written twice (Bluesky, Twitter) and parameterized by two things: which timestamp column to sort on, and how to extract a thread key. That parameterization is done with `method(:bluesky_thread_key)` — passing a bound `Method` object as a first-class callable.
`─────────────────────────────────────────────────`

## What it returns

`call` produces a `Hash` of `section_key => [DraftBlock, ...]` — the assembled draft content for one newsletter edition, bucketed by newsletter section.

```ruby
{ "gems" => [DraftBlock(root: <post>, thread_members: [...]), ...], "articles" => [], ... }
```

## The pipeline, step by step

### 1. Pre-seeded, ordered sections (`empty_sections`)

```ruby
Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
```

`index_with` (ActiveSupport) turns a collection into a hash keyed by its elements. Two things fall out of this:

- **Every** top-level section exists in the result, even empty ones — so the view can render section headers without `nil` guards.
- Ruby hashes preserve insertion order, so **the taxonomy's order becomes the newsletter's order**. Ordering is a data concern here, not a view concern.

`call` then uses `.tap` to mutate that hash in place and return it — a small idiom to avoid a trailing `sections` line.

### 2. The date window

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

Note the **three dots** — an exclusive range. This is the half-open interval `>= start_of_day AND < day_after_end`. It's deliberately not `start.beginning_of_day..end.end_of_day`, because `end_of_day` is `23:59:59.999999` and can silently drop a timestamp landing in the last microsecond. Rails compiles exclusive ranges to `>= ... AND < ...`, so this is both correct and index-friendly.

### 3. Fetching (`bluesky_blocks` / `twitter_blocks`)

Four filters stack up:

| Filter | Meaning |
|---|---|
| `organisation.bluesky_posts` | multi-tenant scoping |
| `where(post_created_at: window, hidden: false)` | in-window, not soft-hidden |
| `where.not(id: excluded_bluesky_ids)` | individually excluded posts |
| `then { without_bluesky_root_exclusions(_1) }` | whole excluded threads |

That `.then { |scope| ... }` is worth noticing: it lets a *conditional* scope be applied mid-chain without breaking the chain into intermediate local variables. The helper returns the scope untouched when there's nothing to exclude, which avoids emitting a `NOT IN ()` against an empty list.

The `includes` is the N+1 defense, and the nesting is the interesting part:

```ruby
author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS }
```

That's two hops: `Bluesky::Post → Bluesky::Author → Author` (the canonical, cross-platform author), then fan out to all of that author's platform accounts. Per the project's model map, `Author` has `has_one :mastodon_account, :twitter_account, :dev_to_account, :bluesky_account` — so the draft view can render any platform handle without extra queries. `snapshot_image_attachment: :blob` does the same for ActiveStorage (attachment *and* blob, since loading only the attachment still triggers a query per blob).

`.to_a` materializes everything once — the rest of the work is pure in-memory Ruby.

### 4. Thread reconstruction (`build_blocks`)

This is the core logic. Social posts arrive as a flat list; the newsletter wants threads collapsed into one block.

```ruby
records.group_by { |record| thread_key.call(record) }
```

The thread key is `thread_root_uri.presence || uri` (Bluesky) or `conversation_id.presence || tweet_id` (Twitter) — i.e. *"the thread I belong to, or myself if I'm standalone."* A standalone post is just a thread of one.

Then, finding the root within each group:

```ruby
root = ordered_records.find { |r| thread_key.call(r) == root_identifier(r) } || ordered_records.first
```

A record is the root when **its thread key equals its own identifier** — a self-referential post. The `|| ordered_records.first` fallback handles the realistic case where the actual root wasn't imported or falls outside the date window: pick the earliest reply instead, so the thread still renders rather than vanishing.

Finally `thread_members: ordered_records - [root]` — the replies, chronologically, with the root pulled out.

`root_identifier` is the one place polymorphism is handled with an explicit `case/when` on class rather than parameterization. Note it returns `nil` for any other type, which would make the `find` fail and fall through to the `first` fallback.

### 5. The two-level exclusion system

`EditionExclusion` is polymorphic (`belongs_to :excludable`), so an editor can exclude any record type from an edition. This class reads it at two granularities:

- **`excluded_*_ids`** — remove exactly this post.
- **`excluded_*_thread_roots`** — remove the *entire thread*. The `filter_map` only collects records where `thread_root_uri.present? && thread_root_uri == uri`, i.e. genuine roots. Excluding a reply removes just that reply; excluding a root removes the whole conversation.

Memoized with the leading-underscore ivar convention the project's style guide requires (`@_excluded_bluesky_ids`).

### 6. Placement (`add_blocks`)

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
next unless sections.key?(section_key)
```

The **root's** section decides where the whole thread lands — replies never split a block across sections. `next unless sections.key?` silently drops anything the taxonomy maps outside the top-level set. The `.fetch(:key)` is a deliberate strictness choice: it raises loudly if the taxonomy entry is malformed, while the unknown-section case is handled quietly.

---

## Two behaviors worth knowing about

**Ordering across sources isn't interleaved.** `call` runs `add_blocks` for Bluesky, then Twitter. Each list is internally sorted by root timestamp, but appending the second list means within any section *all Bluesky blocks precede all Twitter blocks*, regardless of date. If chronological interleaving is the intent, the fix is to concatenate then sort — though the two sources sort on different columns (`post_created_at` vs `tweet_created_at`), which is exactly why it wasn't done. That's likely intentional grouping, but it's implicit.

**`excluded_records` isn't memoized.** It's called twice per platform — once from `excluded_*_ids`, once from `excluded_*_thread_roots` — so that's 4 exclusion queries per `call` where 2 would do. The memoization sits one level too shallow.

**[ASSUMPTION]** — I couldn't verify this against the schema, since the MCP tools aren't connected and the CLI fallback was denied: `where.not(thread_root_uri: [...])` uses SQL `NOT IN`, and in Postgres `NULL NOT IN ('a','b')` evaluates to `NULL`, not `TRUE`. So **rows with a `NULL` `thread_root_uri` are dropped by that filter**, not kept. If standalone posts store `NULL` there rather than their own URI, then the moment an editor excludes any thread root, every standalone post disappears from the draft. The `return scope if ...empty?` guard is what masks this — it only bites when exclusions exist. The same applies to `conversation_id` on the Twitter side. Worth confirming with `rails_get_schema(table:"bluesky_posts")` whether those columns are nullable and how they're backfilled; if they are nullable, the guard needs `.or(scope.where(thread_root_uri: nil))`.
