## What it is

`Edition::DraftQuery` is a **query object** — a read-only service that assembles the raw material for a newsletter edition. Given an `Edition`, it returns a hash shaped exactly like the newsletter's table of contents:

```ruby
{
  'launches'      => [DraftBlock, DraftBlock, ...],
  'events'        => [...],
  'code_and_ruby' => [...],
  ...
  'related'       => [...]
}
```

Every top-level section key is always present, even when empty. The caller (a view/Phlex component) can iterate without any `nil` checks or ordering logic of its own.

`★ Insight ─────────────────────────────────────`
- `empty_sections` (`draft_query.rb:22`) uses `index_with { [] }` over `SectionTaxonomy.ordered_top_level`. Because Ruby hashes preserve insertion order, **the section ordering of the newsletter is baked into the return value itself** — the view never sorts sections. The taxonomy's `order:` integers are the single source of truth.
- The block passed to `index_with` runs per key, so each section gets its *own* array. Had this been `ordered_top_level.zip([[]] * n).to_h`, every section would share one array object — a classic aliasing bug this idiom sidesteps.
- `DraftBlock = Data.define(:root, :thread_members)` (`draft_query.rb:4`) is a Ruby 3.2+ immutable value object. It's declared *inside* the query class, signalling "this shape is this query's output contract," not a domain model.
`─────────────────────────────────────────────────`

## The pipeline

`call` (`draft_query.rb:10`) is deliberately tiny:

```ruby
empty_sections.tap do |sections|
  add_blocks(sections, bluesky_blocks)
  add_blocks(sections, twitter_blocks)
end
```

Build the empty skeleton → pour in Bluesky → pour in Twitter. Everything else is private detail. Four stages happen underneath.

### 1. Date window

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

An **exclusive** range (`...`) whose upper bound is midnight of the day *after* `end_date`. Net effect: both `start_date` and `end_date` are fully included, with no half-open-interval off-by-one and no dependence on `end_of_day`'s `23:59:59.999999` fudge.

### 2. Fetching + exclusions

`bluesky_blocks` and `twitter_blocks` (`draft_query.rb:29` and `:43`) are structurally identical — only the association, timestamp column, and thread-key function differ:

```ruby
edition.organisation.bluesky_posts.
  where(post_created_at: window, hidden: false).
  where.not(id: excluded_bluesky_ids).
  then { |scope| without_bluesky_root_exclusions(scope) }.
  includes(...).
  order(:post_created_at).to_a
```

Exclusions come from `edition.edition_exclusions`, a polymorphic join, and are applied at **two levels**:

| Level | Method | Effect |
|---|---|---|
| Individual | `excluded_bluesky_ids` | drops that one post |
| Whole thread | `excluded_bluesky_thread_roots` | drops every post sharing that `thread_root_uri` |

The second only triggers when the excluded record *is itself a root* — `thread_root_uri.present? && thread_root_uri == uri` (`draft_query.rb:113`). So excluding a root kills the whole thread; excluding a reply kills just the reply.

`★ Insight ─────────────────────────────────────`
- `.then { |scope| without_bluesky_root_exclusions(scope) }` is the idiomatic way to conditionally extend a chain. `where.not(thread_root_uri: [])` would generate a SQL predicate that is *never* true in Postgres, silently zeroing the result — hence the `return scope if ... .empty?` guard at `draft_query.rb:96`. This is a real trap, not defensive noise.
- `includes(author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS })` — note the doubled `author`. A `Bluesky::Post` belongs to a `Bluesky::Author`, which belongs to the canonical `Author`. The nested preload walks that bridge and then fans out to every platform account in one go, so rendering byline links costs zero extra queries.
- `.to_a` is deliberate: the grouping and root-detection that follow are pure Ruby, and materializing once prevents the relation from being re-queried by each pass.
`─────────────────────────────────────────────────`

### 3. Threading — the interesting part

`build_blocks` (`draft_query.rb:57`) collapses a flat list of posts into thread units:

```ruby
records.group_by { |record| thread_key.call(record) }.values.map do |thread_records|
  ordered_records = thread_records.sort_by(&timestamp_method)
  root = ordered_records.find { |r| thread_key.call(r) == root_identifier(r) } || ordered_records.first
  DraftBlock.new(root: root, thread_members: ordered_records - [root])
end
```

The thread key is `thread_root_uri.presence || uri` for Bluesky and `conversation_id.presence || tweet_id` for Twitter — so a standalone post is simply a thread of one, requiring no special case.

Root detection is the clever bit. A record is the root when **its thread key equals its own identifier**:

- Root post: `thread_root_uri` is blank → key falls back to `uri` → matches. Or it's set to its own `uri` → matches.
- Reply: `thread_root_uri` points at the *parent's* uri → doesn't match its own `uri`.

The `|| ordered_records.first` fallback handles the common case where the root itself was filtered out — outside the date window, `hidden`, or individually excluded — by promoting the earliest surviving reply.

`★ Insight ─────────────────────────────────────`
- `ordered_records - [root]` relies on `Array#-` preserving receiver order, so `thread_members` stays chronological. It also uses `eql?`/`hash` — safe here because `root` is literally the same object plucked from that array.
- `root_identifier` (`:69`) is a `case/when` on class with **no `else`**, returning `nil` for an unexpected type. Combined with the `||` fallback, an unknown model degrades to "earliest record is the root" rather than raising. Graceful, but it means a future third platform would silently thread wrong instead of failing loudly.
- Blocks are re-sorted by *root* timestamp (`:66`), not by the thread's latest post. A thread started Monday and continued Friday still appears in Monday's position — the newsletter reads as a chronology of conversation starts.
`─────────────────────────────────────────────────`

### 4. Bucketing into sections

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
next unless sections.key?(section_key)
sections.fetch(section_key) << block
```

Only the **root's** `section` decides placement — replies inherit their root's home, which is what keeps a thread visually intact.

`SectionTaxonomy.for` runs the post's editorial tag through `POST_SECTION_MAP` (`section_taxonomy.rb:19`), a many-to-one funnel: `'code'` and `'post'` both land in `code_and_ruby`; `'video'` and `'slides'` both in `videos`; `'news'`, `'community'`, `'related'` all in `related`. Unknown or `nil` tags fall back to `DEFAULT_POST_SECTION = 'post'` via `post_mapping`, so the lookup can never raise.

The subsection metadata (`Code Samples`, `Slides`, `News`, `Community`) rides along in the same map but is **not** used by this query — `DraftQuery` only groups to top level. Some downstream renderer calls `subsection_for` to split within a section.

## Two things worth your attention

**Thread-root cascade misses roots with a blank `thread_root_uri`.** `excluded_bluesky_thread_roots` requires `thread_root_uri.present?`. If your importer leaves that column `nil` on thread-starting posts (rather than self-referencing), excluding such a root removes only that post — its replies survive, and `build_blocks` promotes the first reply to root. The edition would then show a headless thread. Whether this is live depends on the importer's write behaviour; worth a check.

**`excluded_records` runs four queries.** It's called twice per platform (`draft_query.rb:108`/`:112` and `:118`/`:122`); the memoization is on the two *derived* arrays, not on the shared fetch. Memoizing `excluded_records` itself — keyed by model name — would halve it. Relatedly, `.map(&:excludable)` yields `nil` for any exclusion whose polymorphic target was hard-deleted, and the very next `post.thread_root_uri` would raise `NoMethodError`. A `.compact` there would be cheap insurance.

## Structural takeaway

The two platform methods are near-duplicates that differ only in three parameters — association, timestamp column, thread-key lambda. The author factored the *hard* logic (`build_blocks`) into a shared, parameterised method and left the *easy* query chains duplicated. That's a defensible trade: a `PLATFORMS = [...]` config table would remove ~12 lines but make the actual queries harder to read at a glance. If a third platform (Mastodon) is ever added, that's the point where the balance flips.
