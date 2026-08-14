# How `Edition::DraftQuery` works

`Edition::DraftQuery` is a query object. You hand it an `Edition` and it hands you back the raw material for a newsletter draft: a hash of newsletter sections, each holding an ordered list of social media posts that were grouped back into their original threads.

```ruby
Edition::DraftQuery.new(edition).call
# => { "launches" => [DraftBlock, ...], "events" => [...], ... }
```

Three callers use it: `EditionsController#show` to render the draft screen, `Newsletter::EditionMarkdown` to produce the newsletter markdown, and `Newsletter::SummarizeEditionPostsJob` to walk every post and summarise it.

## The shape of the output

At the top of the class there is a value object:

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A `DraftBlock` is one item in the newsletter. `root` is the post that starts a thread, `thread_members` are the replies that follow it, already sorted by time. A standalone post is just a block with an empty `thread_members`. This is the unit the rest of the newsletter code works with, which is why `EditionsController` and the markdown renderer both build `DraftBlock` instances of their own.

The keys of the returned hash come from `Newsletter::SectionTaxonomy`, the class that owns the eleven newsletter sections (launches, events, code and Ruby, libraries, articles, newsletters, podcasts, videos, books, jobs, related) and their display order.

## The main flow

```ruby
def call
  empty_sections.tap do |sections|
    add_blocks(sections, bluesky_blocks)
    add_blocks(sections, twitter_blocks)
  end
end
```

The whole method reads in three beats.

First, build an empty skeleton:

```ruby
Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
```

`ordered_top_level` returns the section keys sorted by their `order` value, and `index_with` turns that array into a hash where every key points to a fresh empty array. Because Ruby hashes preserve insertion order, the returned hash is already in newsletter order. Every section is present even if nothing lands in it, so views can iterate without checking for nils.

Second, fetch and group posts from each platform. Bluesky and Twitter are handled by two near-identical methods.

Third, `tap` returns the skeleton itself rather than the value of the last `add_blocks` call. The two `add_blocks` calls mutate the hash in place.

## Fetching the posts

Both `bluesky_blocks` and `twitter_blocks` follow the same recipe:

```ruby
edition.organisation.bluesky_posts.
  where(post_created_at: window, hidden: false).
  where.not(id: excluded_bluesky_ids).
  then { |scope| without_bluesky_root_exclusions(scope) }.
  includes(:url_titles,
    author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS },
    snapshot_image_attachment: :blob).
  order(:post_created_at).
  to_a
```

Reading it line by line:

**Scoping to the organisation.** The starting point is `edition.organisation.bluesky_posts`, not `Bluesky::Post.all`. Tenancy is baked into the query.

**The date window.**

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

`start_date` and `end_date` are date columns, but `post_created_at` is a datetime. The window converts both ends to timestamps. It uses an exclusive range (three dots) that ends at midnight of the day after `end_date`, which is the correct way to say "the whole of end_date, inclusive" without hitting the classic off-by-one where posts made at 14:00 on the last day get dropped.

**Manual hiding.** `hidden: false` skips posts an editor marked as hidden at the record level.

**Per-edition exclusions.** `where.not(id: excluded_bluesky_ids)` removes posts the editor excluded from this specific edition. Exclusions live in the `edition_exclusions` table, a polymorphic join that can point at either a `Bluesky::Post` or a `Twitter::Tweet`.

**Thread-level exclusions.** The `then { |scope| ... }` step is the interesting one, covered below.

**Eager loading.** The `includes` call preloads the URL titles, the author chain (a `Bluesky::Author` that belongs to a canonical `Author`, which in turn has its Twitter, Mastodon, Bluesky and Dev.to accounts), and the attached snapshot image with its blob. This is the N+1 defence for a screen that renders dozens of posts with avatars, handles and preview cards.

**Ordering and materialising.** Sorted by creation time, then `to_a` pulls everything into memory. Grouping into threads happens in Ruby, not SQL.

The Twitter version is the same shape with different column names: `tweets` instead of `bluesky_posts`, `tweet_created_at` instead of `post_created_at`.

## Excluding a whole thread by excluding its root

This is the piece of logic that repays a second read:

```ruby
def without_bluesky_root_exclusions(scope)
  return scope if excluded_bluesky_thread_roots.empty?

  scope.where.not(thread_root_uri: excluded_bluesky_thread_roots)
end

def excluded_bluesky_thread_roots
  @_excluded_bluesky_thread_roots ||= excluded_records(Bluesky::Post).filter_map do |post|
    post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
  end
end
```

The rule: excluding a post that is *itself the root of a thread* excludes the entire thread, not just that one post. A post is a root when its `thread_root_uri` equals its own `uri`. `filter_map` collects those root URIs and drops everything else in one pass. Then `where.not(thread_root_uri: ...)` sweeps out every reply that points back at an excluded root.

The guard clause matters. `where.not(column: [])` in ActiveRecord produces a condition that excludes nothing, but returning the scope untouched avoids generating pointless SQL, and it makes the intent explicit.

The `then { |scope| ... }` in the query chain is how this conditional step is threaded into an otherwise linear pipeline without breaking it into intermediate local variables. `then` (also known as `yield_self`) passes the current scope into the block and uses the result as the next link in the chain.

The Twitter equivalent is the same idea with `conversation_id` playing the role of `thread_root_uri` and `tweet_id` playing the role of `uri`.

## Grouping flat records back into threads

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

`build_blocks` is the shared engine both platforms feed into. It is parameterised rather than duplicated, and the parameters are worth noting: `timestamp_method` is a symbol (`:post_created_at` or `:tweet_created_at`) and `thread_key` is a `Method` object created with `method(:bluesky_thread_key)`. Passing a bound method as a first-class value is what lets the same algorithm serve two schemas.

The thread key itself is defensive:

```ruby
def bluesky_thread_key(post)
  post.thread_root_uri.presence || post.uri
end
```

If the post has no `thread_root_uri`, it is treated as its own thread of one. `presence` handles both nil and empty string.

The grouping then works in four moves:

1. `group_by(&thread_key)` buckets records by thread. `.values` discards the keys because only the buckets matter from here.
2. Each bucket is sorted chronologically.
3. The root is the record whose thread key equals its own identifier (`uri` for Bluesky, `tweet_id` for Twitter). The `|| ordered_records.first` fallback covers the case where the actual root post is not in the result set, perhaps because it fell outside the date window or was hidden. Rather than dropping the thread, the earliest surviving reply is promoted to root.
4. `ordered_records - [root]` removes the root from the members list. `Data` objects use value equality, but these are ActiveRecord objects, so `-` compares by `id` here and removes exactly one record.

Finally the blocks are re-sorted by their root's timestamp. Without this the block order would follow whatever order `group_by` produced, which reflects the first appearance of each thread rather than each thread's start time.

`root_identifier` is a small `case/when` on class:

```ruby
def root_identifier(record)
  case record
  when Bluesky::Post then record.uri
  when Twitter::Tweet then record.tweet_id
  end
end
```

It returns `nil` for anything else, which would make the `find` fail and quietly fall back to `ordered_records.first`.

## Filing blocks into sections

```ruby
def add_blocks(sections, blocks)
  blocks.each do |block|
    section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
    next unless sections.key?(section_key)

    sections.fetch(section_key) << block
  end
end
```

The block's section comes from its *root* post. Replies do not get their own placement, which is what you want: a thread is one newsletter item.

`SectionTaxonomy.for` maps a post-level section value (`'launch'`, `'code'`, `'podcast'`, `'news'`) to a top-level newsletter section, falling back to `'post'` (so `'code_and_ruby'`) for anything unrecognised or blank. That is why several post sections collapse into one newsletter section: `'post'` and `'code'` both land in `code_and_ruby`, `'video'` and `'slides'` both land in `videos`.

The `next unless sections.key?` line is belt and braces. `SectionTaxonomy.for` uses `fetch` internally and always returns a known section, so in practice the guard never fires. It exists so a future taxonomy change cannot raise a `KeyError` in the middle of rendering a draft.

Note that the two platforms are appended in sequence: all Bluesky blocks first, then all Twitter blocks. Within a section, posts are ordered by platform and then chronologically inside each platform, not strictly chronologically across both.

## Memoisation and query count

The four exclusion methods all memoise:

```ruby
def excluded_bluesky_ids
  @_excluded_bluesky_ids ||= excluded_records(Bluesky::Post).map(&:id)
end
```

They need to, because both `excluded_bluesky_ids` and `excluded_bluesky_thread_roots` call `excluded_records(Bluesky::Post)`, and each of those is a database round trip:

```ruby
def excluded_records(model)
  edition.edition_exclusions.where(excludable_type: model.name).includes(:excludable).map(&:excludable)
end
```

The memoisation is on the two public-facing methods rather than on `excluded_records` itself, so `excluded_records(Bluesky::Post)` still runs twice on a cold object. The `includes(:excludable)` preloads the polymorphic target so `map(&:excludable)` does not fire one query per exclusion.

Worth remembering: the memoised instance variables mean a `DraftQuery` instance is meant to be used once and thrown away. `Edition::DraftQuery.new(edition).call` is the intended usage, and all three call sites follow it.

## What the design is doing

A few things stand out about how this class is put together.

**Sandi Metz-sized methods.** Nearly every method is one to five lines. `call` reads as a summary of the whole class. Nothing requires scrolling.

**Structural duplication, not logical duplication.** The Bluesky and Twitter paths look copy-pasted, but they are not: the shared algorithm lives in `build_blocks`, and only the column names and identifier fields differ. Collapsing the two fetch methods further would need a configuration hash or an adapter class, which would trade readability for a small amount of line count. The current split is the more honest version.

**Composition over conditionals.** `then { ... }` keeps the optional thread-exclusion filter inside the query chain. `method(:bluesky_thread_key)` keeps the platform difference as a parameter rather than a branch inside `build_blocks`.

**Defensive fallbacks everywhere.** Missing thread root, unknown section, empty exclusion list, non-matching record class. Each has a sensible default, and none of them raise. For a draft-generation screen that an editor is staring at, degrading gracefully is worth more than failing loudly.

**Read-only.** Nothing here writes. It is a pure function of `(edition, database state)`, which is why the same object can safely back a controller action, a markdown renderer, and a background job.
