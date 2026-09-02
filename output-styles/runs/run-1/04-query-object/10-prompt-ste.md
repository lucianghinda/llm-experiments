Note: the `rails ai:*` MCP tools aren't connected here, and the CLI fallback (`bin/rails 'ai:tool[search_code]'`) wasn't approved, so anything about the collaborator classes below is marked `[ASSUMPTION]` — it's inferred from how this file calls them, not verified.

# What this class does

`Edition::DraftQuery` builds the **draft content of one newsletter edition**. You give it an `Edition`; it gives you back a hash:

```
{ section_key => [DraftBlock, DraftBlock, ...], ... }
```

Each `DraftBlock` is one social-media thread: a `root` post plus the `thread_members` (the replies that follow it).

# Step by step

**1. The value object (line 4)**

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

An immutable struct. A thread of 3 posts becomes 1 block, not 3 items.

**2. `call` (lines 10–15)**

```ruby
empty_sections.tap do |sections|
  add_blocks(sections, bluesky_blocks)
  add_blocks(sections, twitter_blocks)
end
```

Start with an empty hash of sections, fill it with Bluesky blocks, then Twitter blocks, return it. `tap` returns the hash itself, not the return value of the block.

**3. `empty_sections` (line 22)**

`Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }` — one key per top-level section, each starting as an empty array. Because it comes from `ordered_top_level`, **the hash already has the correct section order**, and later steps only ever push into existing keys — sections are never added or reordered.

**4. `window` (line 26)**

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

A half-open range (`...`, exclusive end): from midnight on the start date up to — but not including — midnight after the end date. Net effect: **the full end date is included**, with no risk of catching a post at exactly 00:00:00 on the following day.

**5. `bluesky_blocks` / `twitter_blocks` (lines 29–55)**

These two are the same shape, only the column and identifier names differ. Each one:

- scopes to the edition's organisation (`edition.organisation.bluesky_posts` / `.tweets`)
- keeps posts inside `window` and `hidden: false`
- removes individually excluded records (`where.not(id: excluded_*_ids)`)
- removes **whole threads** whose root was excluded (`without_*_root_exclusions`)
- `includes(...)` preloads url titles, the author chain, and the snapshot image blob — this is N+1 prevention, since the newsletter view renders all of those
- orders by creation time and calls `to_a` (loads it into memory once; grouping happens in Ruby, not SQL)

**6. `build_blocks` (lines 57–67) — the interesting part**

```ruby
records.group_by { |record| thread_key.call(record) }.values.map do |thread_records|
  ordered_records = thread_records.sort_by(&timestamp_method)
  root = ordered_records.find { |r| thread_key.call(r) == root_identifier(r) } || ordered_records.first
  DraftBlock.new(root: root, thread_members: ordered_records - [root])
end
```

- Group all records by thread key → each group is one thread.
- Sort each group by time.
- Find the **real root**: the record whose thread key equals its own identifier. A root post points at itself (`thread_root_uri == uri`, or `conversation_id == tweet_id`), so this test identifies the thread starter.
- `|| ordered_records.first` is the fallback: if the real root isn't in the result set (it fell outside the date window, or was hidden), the earliest surviving post is promoted to root. So a thread never disappears just because its first post was filtered out.
- `ordered_records - [root]` removes the root by Active Record identity (`==`/`hash` compare on id), leaving the replies.
- Finally the blocks are sorted by their root's timestamp — chronological order.

The two `thread_key` helpers (lines 87–93) encode the same "point at yourself if you're the root" rule: `thread_root_uri.presence || uri`, `conversation_id.presence || tweet_id`. `presence` handles empty strings, not just `nil`.

**7. `add_blocks` (lines 78–85)**

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
next unless sections.key?(section_key)
sections.fetch(section_key) << block
```

The block's section comes **from its root post only** — replies do not vote. `next unless sections.key?` silently drops blocks whose section is not a top-level one. `fetch` (rather than `[]`) means a taxonomy shape change fails loudly instead of returning `nil`.

**8. Exclusions (lines 95–129)**

`edition.edition_exclusions` is a polymorphic list of records an editor removed by hand. There are two levels:

| Level | Method | Effect |
|---|---|---|
| Single record | `excluded_bluesky_ids` / `excluded_twitter_ids` | that one post is dropped |
| Whole thread | `excluded_*_thread_roots` | if the excluded record **is itself a root**, every post in that thread is dropped |

`filter_map` on lines 112 and 122 does the "is it a root?" test (`thread_root_uri == uri`) and collects the value in one pass. The `without_*_root_exclusions` guards return the scope untouched when the list is empty, avoiding a `WHERE NOT IN ()` on every query. Results are memoized in `@_`-prefixed variables, per this project's style rule.

# Two behaviours worth knowing

- **Bluesky and Twitter are not interleaved.** `call` appends all Bluesky blocks, then all Twitter blocks. Inside a section, blocks are chronological *per platform*, but every Bluesky block still comes before every Twitter one. If you wanted one merged timeline per section, you'd sort each section's array after both `add_blocks` calls.
- **`excluded_records` (line 127) is not memoized**, while its four callers are. It runs a fresh query each time it's called — twice for Bluesky, twice for Twitter, so 4 queries where 2 would do. Memoizing it by model name would make it 2.
