`★ Insight ─────────────────────────────────────`
- This class is a **query object**, not a service in the "call an external API" sense — it takes one `Edition` and returns a fully-shaped, ready-to-render data structure, keeping that assembly logic out of both the model and the controller.
- It uses `Data.define` (Ruby 3.2+) for `DraftBlock` — an immutable value object that gives the view a named vocabulary (`block.root`, `block.thread_members`) instead of raw tuples or hashes.
- The whole class is built around one problem: social posts arrive as *individual rows*, but a newsletter draft wants them as *threads*. Most of the code is thread reconstruction and exclusion handling.
`─────────────────────────────────────────────────`

## What it returns

`#call` (line 10) returns a Hash shaped like:

```ruby
{ section_key_a => [DraftBlock, DraftBlock, ...],
  section_key_b => [...] }
```

Every top-level newsletter section is a key, pre-seeded with an empty array by `empty_sections` (line 21) via `index_with { [] }`. That's a deliberate choice: the view can iterate all sections and render "nothing here yet" states without `nil` guards, and section *order* comes from the taxonomy rather than from whatever data happens to exist.

`tap` on line 11 is doing "build the accumulator, mutate it twice, return it" — Bluesky posts and tweets both get folded into the same section buckets.

## The pipeline, step by step

**1. Time window** (line 25)

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

Note the **three-dot exclusive range**. `end_date.tomorrow.beginning_of_day` is the first instant *after* the edition's last day, and excluding it means the window is "the whole of start_date through the whole of end_date" with no off-by-one at midnight. This is the correct pattern for timestamp columns — `start_date..end_date` would silently drop everything posted after midnight on the final day.

**2. Fetch + filter** (lines 29–55)

Bluesky and Twitter are structurally identical, differing only in column names (`post_created_at` vs `tweet_created_at`, `uri` vs `tweet_id`, `thread_root_uri` vs `conversation_id`). Each scope:

- filters to the window and `hidden: false`
- drops individually excluded records (`where.not(id: ...)`)
- drops whole threads whose *root* was excluded (`then { |scope| ... }`)
- eager-loads `:url_titles`, nested author accounts, and the attached snapshot image + blob
- orders chronologically, then `to_a`

The `.then { |scope| without_bluesky_root_exclusions(scope) }` is a neat trick: it keeps the chain readable while letting a method conditionally add a clause. Without it you'd need an intermediate variable, because `without_...` needs to return the scope *unchanged* when there's nothing to exclude (line 96) — adding `where.not(thread_root_uri: [])` would be wasteful SQL.

`includes(..., snapshot_image_attachment: :blob)` is the standard fix for the N+1 that ActiveStorage otherwise causes when a view asks each record for its image.

**3. Two levels of exclusion**

This is the subtlest part of the class:

| Method | Effect |
|---|---|
| `excluded_bluesky_ids` (107) | Remove *just that post* |
| `excluded_bluesky_thread_roots` (111) | Remove the *entire thread* |

The second one only collects a root identifier when `post.thread_root_uri == post.uri` — i.e. the excluded post **is itself the root of a thread**. So excluding a reply removes one post; excluding a thread's opening post removes the whole thread. Twitter mirrors this with `conversation_id == tweet_id` (line 123).

All four are memoized with the leading-underscore ivar convention this project requires (`@_excluded_bluesky_ids`). Worth noting `excluded_records` (line 127) is *not* memoized, so it runs one query per caller — with two callers per platform that's 4 queries where 2 would do. Minor, but it's the one place the caching is incomplete.

**4. Grouping into threads** (line 57)

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`thread_key` is passed in as `method(:bluesky_thread_key)` — a `Method` object used as a first-class function so `build_blocks` stays platform-agnostic. The key is `thread_root_uri.presence || uri`: a standalone post is a thread of one, keyed by itself.

Within each thread it sorts chronologically, then picks the root as the record whose thread key equals its own identifier (line 60) — the post that starts the thread. The `|| ordered_records.first` fallback handles the real-world case where the actual root wasn't imported or fell outside the window, so the earliest surviving reply is promoted. `thread_members` is then everything else, in time order.

Finally blocks are sorted by their root's timestamp (line 66), so the draft reads chronologically by thread, not by individual post.

**5. Bucketing into sections** (line 78)

Each block's section comes from its **root** post only — replies inherit their thread's placement. `next unless sections.key?(section_key)` silently drops anything mapping to a section that isn't top-level, which keeps the output guaranteed-consistent with `empty_sections`.

`★ Insight ─────────────────────────────────────`
- `method(:bluesky_thread_key)` + `timestamp_method` as a symbol is duck-typing across two models that share no ancestor. An alternative would be a shared concern exposing `#thread_key` and `#published_at`; the current approach avoids touching the models at the cost of `root_identifier`'s `case/when` (line 69) needing an edit for every new platform.
- `root_identifier` returns `nil` for any class that isn't `Bluesky::Post` or `Twitter::Tweet` — combined with the `|| ordered_records.first` fallback, a third platform would silently "work" while always treating the earliest record as root. That's the spot to watch if Mastodon posts ever join the draft.
`─────────────────────────────────────────────────`

Two things I did **not** verify in this session, since the MCP tools aren't connected and the CLI fallback wasn't approved: `[ASSUMPTION]` `Newsletter::SectionTaxonomy` responds to `.ordered_top_level` and `.for(section) → { key: ... }`, and `Author::PLATFORM_ACCOUNT_ASSOCIATIONS` is an array of the platform account association names — both read that way from usage here, but I'm inferring them rather than confirming.
