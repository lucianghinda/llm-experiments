# How `Edition::DraftQuery` works

`Edition::DraftQuery` is a query object. You give it an `Edition` and it gives you back the whole content of a newsletter draft, already fetched, already grouped into threads, and already sorted into newsletter sections. It is the single source of truth for "what goes in this edition", used by `EditionsController#show`, by `Newsletter::EditionMarkdown`, and by `Newsletter::SummarizeEditionPostsJob`.

## The shape of the result

`call` returns an ordered `Hash`:

```ruby
{
  "launches"      => [DraftBlock, DraftBlock, ...],
  "events"        => [...],
  "code_and_ruby" => [...],
  ...
  "related"       => [...]
}
```

The keys come from `Newsletter::SectionTaxonomy.ordered_top_level`, so every section defined in the taxonomy is present in its canonical order, even when it has no content. That is what `empty_sections` does:

```ruby
Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
```

`index_with` turns the list of keys into a hash where every value is a fresh empty array. Callers can then iterate the hash and always get the sections in the right order, and views can safely check `blocks.any?` without worrying about missing keys.

The values are `DraftBlock` instances:

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A `Data` object, so it is immutable and compares by value. A block is one entry in the newsletter: the `root` post plus the rest of its thread in `thread_members`, sorted chronologically. A standalone post is a block with an empty `thread_members` array. The class is public enough that `EditionsController#hidden` builds `DraftBlock`s by hand for the "hidden posts" screen, reusing the same rendering partials.

`call` itself is three lines:

```ruby
empty_sections.tap do |sections|
  add_blocks(sections, bluesky_blocks)
  add_blocks(sections, twitter_blocks)
end
```

Build the skeleton, pour Bluesky content into it, pour Twitter content into it, return the skeleton. `tap` is there so the hash is the return value rather than the result of the last `add_blocks`.

## The date window

```ruby
def window
  edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
end
```

Editions store `start_date` and `end_date` as dates, but posts carry timestamps. The window converts the dates into a half open timestamp range: from midnight on the start date up to, but not including, midnight after the end date. The three dot range is deliberate. A post created at 23:59 on the end date is inside the edition, and a post created at 00:00 the next day is not. Rails translates that into a `BETWEEN`-style condition with an exclusive upper bound, so it uses the timestamp index instead of casting every row to a date.

## Fetching the records

`bluesky_blocks` and `twitter_blocks` are deliberately parallel:

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

Reading it top to bottom:

1. **Start from the organisation, not from the model.** `edition.organisation.bluesky_posts` scopes everything to the tenant that owns the edition. A post belonging to another organisation can never leak into a draft, and the test suite has a case for exactly that.
2. **Filter by window and by the `hidden` flag.** `hidden` is a per-post boolean on the table. It is a global "never show this anywhere" switch, different from the per-edition exclusions below.
3. **Drop individually excluded records** by primary key.
4. **Drop whole excluded threads** through `then { ... }`. This is the interesting bit of chaining. `then` (also known as `yield_self`) passes the current scope to a method and continues the chain with whatever comes back. The helper adds a condition only when there is something to exclude:

   ```ruby
   def without_bluesky_root_exclusions(scope)
     return scope if excluded_bluesky_thread_roots.empty?

     scope.where.not(thread_root_uri: excluded_bluesky_thread_roots)
   end
   ```

   Without `then`, you would have to break the chain into a local variable and a conditional reassignment. With it, the conditional lives inside a named method and the chain stays flat. The guard clause matters for correctness too, because `where.not(column: [])` in Rails produces a condition that would behave differently from "no filter at all".
5. **Eager load everything the draft view touches.** `url_titles` for link previews, `author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS }` to walk from the platform author to the unified `Author` record and then to all its platform accounts, and `snapshot_image_attachment: :blob` so `snapshot_image.attached?` does not fire a query per post. There is a test that renders every record's author name, author URL, and attachment status inside `assert_no_queries`, which pins this preload list to the actual rendering path.
6. **Order by the platform timestamp** and call `to_a` to run the query once and work in memory from there.

The Twitter version is the same code with `tweets`, `tweet_created_at`, and `conversation_id`. Mastodon posts are never queried, which the tests assert explicitly.

## Grouping into threads

The two fetch methods hand off to one shared builder, parameterised by the timestamp column and by a thread key function:

```ruby
build_blocks(records, :post_created_at, method(:bluesky_thread_key))
```

`method(:bluesky_thread_key)` wraps a private method into a callable `Method` object. That is how `build_blocks` stays platform agnostic without any conditionals inside it.

The thread key is the identity of the conversation a record belongs to:

```ruby
def bluesky_thread_key(post)
  post.thread_root_uri.presence || post.uri
end
```

If the post is part of a thread, the key is the thread root URI. If not, the key is the post's own URI, so a standalone post forms a group of one. The Twitter version uses `conversation_id` with a fallback to `tweet_id`.

`build_blocks` then does the actual work:

```ruby
blocks = records.group_by { |record| thread_key.call(record) }.values.map do |thread_records|
  ordered_records = thread_records.sort_by(&timestamp_method)
  root = ordered_records.find do |record|
    thread_key.call(record) == root_identifier(record)
  end || ordered_records.first
  DraftBlock.new(root: root, thread_members: ordered_records - [root])
end

blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

Group by thread key, sort each group chronologically, then pick the root. A record is the root of its own thread when its thread key equals its own identifier, which is `uri` for Bluesky and `tweet_id` for Twitter. That is the same condition as the `thread_root?` predicate on the models, expressed here without an extra method call per platform.

The `|| ordered_records.first` fallback handles a real case: a thread whose root was posted before the edition window but whose reply lands inside it. The root was filtered out by the date query, so no record in the group is its own root, and the earliest reply present is promoted to root. It becomes a block on its own, which the tests cover as the "orphan member" case.

Finally, blocks are sorted by their root's timestamp, so within a platform the newsletter reads in chronological order.

One consequence of `call` adding Bluesky first and Twitter second: inside a given section, all Bluesky blocks come before all Twitter blocks, each run chronological within itself. There is no global merge by timestamp across platforms.

## Placing blocks into sections

```ruby
def add_blocks(sections, blocks)
  blocks.each do |block|
    section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
    next unless sections.key?(section_key)

    sections.fetch(section_key) << block
  end
end
```

The root's `section` value (an enum backed by `ContentType::SECTIONS`) is mapped through the taxonomy into a newsletter section. `SectionTaxonomy.for` falls back to the `post` mapping for unknown or `nil` values, which lands in `code_and_ruby`, so an unclassified post still shows up somewhere instead of disappearing. The tests confirm that a post with a `nil` section ends up in `code_and_ruby`.

Two details worth noticing. The `next unless sections.key?(section_key)` guard is defensive: if the taxonomy ever maps something to a key that is not a top level section, the block is skipped rather than creating a stray key. And the whole thread is placed by the **root's** section. If a reply in the thread is tagged differently, that tag is ignored, which is what you want because the thread is published as a single unit.

The use of `fetch` in three places instead of `[]` is a small consistency: the code prefers to blow up loudly on a missing key rather than silently work with `nil`.

## The exclusion system

`edition_exclusions` is a polymorphic join between an edition and any excludable record. It powers the "hide this from the draft" button in the UI. The query object reads it in two different ways.

```ruby
def excluded_records(model)
  edition.edition_exclusions.where(excludable_type: model.name).includes(:excludable).map(&:excludable)
end
```

This loads the actual excluded records for one model class, preloading `excludable` so mapping over them does not trigger one query per exclusion.

From that list, two things are derived:

```ruby
def excluded_bluesky_ids
  @_excluded_bluesky_ids ||= excluded_records(Bluesky::Post).map(&:id)
end

def excluded_bluesky_thread_roots
  @_excluded_bluesky_thread_roots ||= excluded_records(Bluesky::Post).filter_map do |post|
    post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
  end
end
```

The first is a plain list of primary keys, used to drop individually hidden records. The second keeps only the exclusions that are themselves thread roots, and collects their thread identifiers. Those identifiers then remove every record sharing that thread root from the query.

The result is a deliberate asymmetry in behaviour, and the tests spell it out:

- Hiding a **thread root** hides the entire thread, root and all replies.
- Hiding a **thread member** hides only that reply, and the rest of the thread still renders.

Exclusions are also scoped to `edition.edition_exclusions`, so hiding a post in edition 171 has no effect on edition 172. That is the difference from the `hidden` column, which is global and permanent.

`filter_map` is used instead of `map` plus `compact`, so non-root exclusions produce nothing rather than a `nil` that has to be cleaned up afterwards.

## Query cost

For a full `call`, the database work is:

- 4 queries for exclusions (ids and thread roots, for each of two platforms), because the memoization sits on the four public-facing helper methods rather than on `excluded_records` itself. Each of those helper methods calls `excluded_records` once, and each call is a real round trip.
- 2 main queries, one per platform, plus their preload queries for `url_titles`, authors, platform accounts, attachments, and blobs.

Everything after that is in-memory grouping and sorting over arrays that were already materialised with `to_a`. Nothing in `build_blocks`, `add_blocks`, or `root_identifier` can trigger a lazy load, which is why the "no queries during rendering" test passes.

## The design in one sentence

The class isolates one messy job (pull two platforms' worth of posts for a date range, respect two different kinds of hiding, reassemble threads, and file them into newsletter sections) behind a two-line public interface, so the controller, the markdown exporter, and the summarization job all see exactly the same draft without duplicating any of that logic.
