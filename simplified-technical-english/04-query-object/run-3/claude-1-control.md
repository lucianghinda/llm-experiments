# `Edition::DraftQuery`

## What it does

`Edition::DraftQuery` is a query object. You give it an `Edition` and it returns the draft content for that edition's newsletter, already grouped and ordered so a view or a Markdown renderer can print it directly.

The return value is a `Hash`:

- keys: the newsletter section keys, in publication order (`launches`, `events`, `code_and_ruby`, ... `related`)
- values: arrays of `DraftBlock` structs

Every section key is always present, even when it has no content. Callers therefore never have to check for a missing key.

It reads from two sources only: Bluesky posts and tweets. Mastodon posts and other content types are not touched.

## Where it is used

- `EditionsController#show` — builds `@sections` for the draft preview page
- `Newsletter::EditionMarkdown` — keeps only the sections that have blocks, then renders Markdown
- `Newsletter::SummarizeEditionPostsJob` — walks the blocks to enqueue AI summaries

The class is read-only. It never writes to the database.

## The `DraftBlock` value object

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A block is one newsletter item. `root` is the post that opens a thread (or a standalone post). `thread_members` holds the rest of the thread, in chronological order, with the root removed. A standalone post gives a block with an empty `thread_members`.

Using `Data.define` makes the block immutable and gives it value equality, which is why the tests can compare blocks with `assert_equal`.

## The main flow

```ruby
def call
  empty_sections.tap do |sections|
    add_blocks(sections, bluesky_blocks)
    add_blocks(sections, twitter_blocks)
  end
end
```

Three steps:

1. Build a hash with one empty array per section.
2. Load Bluesky posts, turn them into blocks, drop each block into its section.
3. Do the same for tweets.

`tap` is used so `call` returns the hash rather than the result of the last `add_blocks`.

### 1. `empty_sections`

```ruby
Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
```

`ordered_top_level` sorts the taxonomy by its `:order` field and returns the keys. `index_with` (ActiveSupport) turns that array into a hash where each key maps to a fresh empty array. The block form matters — `index_with([])` would give every key the *same* array object.

This is where the section ordering of the final result comes from. Ruby hashes keep insertion order, so the caller iterates sections in newsletter order for free.

### 2. `window`

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

The edition stores `start_date` and `end_date` as dates, but posts carry timestamps. The window converts the dates to a timestamp range.

Note the three dots — an *exclusive* end range. The end is midnight of the day *after* `end_date`, and that instant is excluded. Result: the whole of `end_date` is inside the window, and nothing on the next day is. This is the "include start boundary and last in-window post, exclude the next-day boundary" behaviour the tests assert.

Passing a Ruby range to `where` makes ActiveRecord emit `>= ... AND < ...`, so the boundary semantics survive into SQL.

### 3. Loading records

`bluesky_blocks` and `twitter_blocks` are the same shape, differing only in association name, timestamp column, and thread key column:

```ruby
records = edition.organisation.bluesky_posts.
          where(post_created_at: window, hidden: false).
          where.not(id: excluded_bluesky_ids).
          then { |scope| without_bluesky_root_exclusions(scope) }.
          includes(:url_titles,
            author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS },
            snapshot_image_attachment: :blob).
          order(:post_created_at).
          to_a
```

Reading the chain:

- **`edition.organisation.bluesky_posts`** — multi-tenant scoping. Only the edition owner's content is considered.
- **`where(post_created_at: window, hidden: false)`** — inside the date window, and not manually hidden. `hidden` is a boolean column on both tables with a `false` default.
- **`where.not(id: excluded_bluesky_ids)`** — drops posts the editor excluded from *this* edition.
- **`.then { ... }`** — used purely so the conditional thread-root filter can sit inside the chain instead of breaking it into a local variable. `then` (a.k.a. `yield_self`) passes the relation to the block and uses the block's return value.
- **`includes(...)`** — eager loading to avoid N+1 in the draft view. It preloads link titles, the nested author chain (`Bluesky::Post#author` is a `Bluesky::Author`, which itself belongs to a canonical `Author`, which has the four platform accounts), and the Active Storage attachment plus blob for the post snapshot image. There is a test that renders these associations inside `assert_no_queries`, so the eager-load list is load-bearing, not decorative.
- **`order(:post_created_at)`** — chronological, which `build_blocks` relies on.
- **`to_a`** — forces the query. From here on everything is in Ruby memory.

### 4. Exclusions

Editors can remove individual items from an edition. This is stored in `edition_exclusions`, a polymorphic join (`edition_id`, `excludable_type`, `excludable_id`).

```ruby
def excluded_records(model)
  edition.edition_exclusions.where(excludable_type: model.name).includes(:excludable).map(&:excludable)
end
```

Exclusions are scoped to the edition, so excluding a post from edition 171 does not affect edition 172.

Exclusion works at two levels:

**Individual records.** `excluded_bluesky_ids` / `excluded_twitter_ids` collect the excluded record ids and feed the `where.not(id: ...)` clause. Excluding a thread *member* removes only that member; the root and the other members stay.

**Whole threads.** `excluded_bluesky_thread_roots` / `excluded_twitter_thread_roots` collect the excluded records that are thread roots:

```ruby
post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
```

A record is a thread root when its thread key equals its own identifier — the same test as `Bluesky::Post#thread_root?` and `Twitter::Tweet#thread_root?`, inlined here because these are plain in-memory records. `filter_map` keeps the non-nil values.

Those root identifiers then power a second filter:

```ruby
def without_bluesky_root_exclusions(scope)
  return scope if excluded_bluesky_thread_roots.empty?

  scope.where.not(thread_root_uri: excluded_bluesky_thread_roots)
end
```

Every post whose `thread_root_uri` matches an excluded root disappears — the root and all its replies. The early return avoids generating a `NOT IN ()` clause when there is nothing to exclude. The Twitter version is identical with `conversation_id`.

So the rule is: **exclude a member, lose the member; exclude the root, lose the whole thread.**

All four exclusion helpers are memoized with `@_name ||=`, because each is read at least twice per call and each triggers its own database query.

### 5. Grouping into blocks

```ruby
def build_blocks(records, timestamp_method, thread_key)
  blocks = records.group_by { |record| thread_key.call(record) }.values.map do |thread_records|
    ordered_records = thread_records.sort_by(&timestamp_method)
    root = ordered_records.find do |record|
      thread_key.call(record) == root_identifier(record)
    end || ordered_records.first
    DraftBlock.new(root: root, thread_members: ordered_records - [root])
  end

  blocks.sort_by { |block| block.root.public_send(timestamp_method) }
end
```

This is the shared threading logic. The platform differences are passed in as parameters: a symbol for the timestamp column and a `Method` object (`method(:bluesky_thread_key)`) for the key extraction. Passing `method(...)` rather than a symbol is what lets the key function be a private method of this class instead of a method on the record.

The thread keys:

```ruby
def bluesky_thread_key(post) = post.thread_root_uri.presence || post.uri
def twitter_thread_key(tweet) = tweet.conversation_id.presence || tweet.tweet_id
```

A post in a thread keys on the thread root; a standalone post keys on itself. `presence` handles empty strings as well as `nil`. This means standalone posts each become their own single-record group, so they flow through the same code path as threads — no special case needed.

Then per group:

- sort by timestamp (chronological order inside the thread)
- find the record that *is* the root, by comparing its thread key against its own identifier (`uri` for Bluesky, `tweet_id` for Twitter, via `root_identifier`)
- if no such record is present, fall back to the earliest record

That fallback matters for a real case the tests cover: a reply that falls inside the edition window while the thread's actual root was posted earlier, outside the window. The root was never loaded, so no record satisfies the root test, and the earliest loaded reply is promoted to root of its own single-item block.

`ordered_records - [root]` uses `Array#-`, which relies on `hash`/`eql?`. Two ActiveRecord instances of the same class and id are equal, so the root is removed reliably.

Finally the blocks are sorted by their root's timestamp, so sections list items oldest first.

### 6. Placing blocks into sections

```ruby
def add_blocks(sections, blocks)
  blocks.each do |block|
    section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
    next unless sections.key?(section_key)

    sections.fetch(section_key) << block
  end
end
```

The *root's* `section` value decides where the whole block goes; thread members do not vote.

`SectionTaxonomy.for` maps a post-level section (`launch`, `library`, `podcast`, `code`, `news`, ...) to a top-level newsletter section. Posts with an unrecognised or `nil` section fall back through `DEFAULT_POST_SECTION` (`'post'`) to `code_and_ruby`, so nothing is silently dropped for lack of a section. Several post sections collapse into one newsletter section — `code` joins `code_and_ruby`, `slides` joins `videos`, `news` and `community` join `related`.

`fetch` is used instead of `[]` throughout: a missing key raises instead of yielding a `nil` that would surface as a confusing error later. The `next unless sections.key?(section_key)` guard is the one deliberately soft path — a taxonomy entry not present in the top-level list would be skipped rather than crash.

Bluesky blocks are added before Twitter blocks. Because both are appended to the same per-section arrays, a section holds its Bluesky blocks (chronological) followed by its Twitter blocks (chronological), not a single merged chronological list.

## Design notes

**Query object shape.** `initialize` + a single public `call`, everything else private, `attr_reader :edition` private. No side effects, no persistence — the caller decides what to do with the result.

**Reads happen up front.** All database access finishes in the two `*_blocks` methods; grouping, root detection, sorting, and section assignment are pure Ruby over arrays. That keeps the logic easy to test and avoids issuing queries inside loops.

**Duplication between platforms is deliberate and shallow.** `bluesky_blocks` and `twitter_blocks` look near-identical, but the two models use different column names for the same concepts. The real algorithm lives once in `build_blocks`; the per-platform methods only supply the column names and the key function. `root_identifier` is the one place that switches on class with a `case/when`.

**Empty-section contract.** Returning every section key, always, moves the "does this section exist?" question out of the callers. `Newsletter::EditionMarkdown` filters empties itself with `select { |_key, blocks| blocks.any? }` when it wants only the populated ones.

## Things to watch

- `excluded_records` is called twice per platform (once for ids, once for roots), and each call re-queries `edition_exclusions`. The *results* of the two public helpers are memoized, but the underlying fetch is not shared between them — four queries where two would do.
- Both `*_blocks` methods call `to_a` and hold every in-window post in memory. Fine for a weekly newsletter window; it would need paging for a much larger range.
- `add_blocks` mutates the hash passed to it. It is private and only called from `call`, so the mutation is contained, but the method is not usable as a pure transformation.
- The ordering within a section is Bluesky-then-Twitter rather than fully chronological. If a mixed chronological order were wanted, the two block lists would need merging before `add_blocks`.
