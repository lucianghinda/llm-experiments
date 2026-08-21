# `Edition::DraftQuery`

## What the class does

`Edition::DraftQuery` is a query object. It takes one `Edition` and it gives back
the draft content of the newsletter for that edition.

The class reads Bluesky posts and Twitter tweets of the organisation. It keeps only
the records in the date window of the edition. It puts related posts together into
threads. Then it sorts the threads into the newsletter sections.

Three callers use the class:

- `EditionsController#show` shows the sections on the edition page.
- `Newsletter::EditionMarkdown` writes the Markdown export.
- `Newsletter::SummarizeEditionPostsJob` reads the blocks to make summaries.

## The result

`#call` gives back a `Hash`:

- Each key is a newsletter section key, for example `'launches'` or `'articles'`.
- Each value is an `Array` of `DraftBlock`.
- The keys are in the order of `Newsletter::SectionTaxonomy.ordered_top_level`.
- Sections with no content stay in the `Hash` as empty arrays.

`DraftBlock` is a small value object:

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

`root` is the first post of a thread. `thread_members` is an `Array` of the other
posts of the same thread, in time order. A post that is alone gets a block with an
empty `thread_members` array.

`Data.define` makes the object immutable. The block holds the model records, not
copies of their data.

## How `#call` works

```ruby
def call
  empty_sections.tap do |sections|
    add_blocks(sections, bluesky_blocks)
    add_blocks(sections, twitter_blocks)
  end
end
```

There are three steps:

1. `empty_sections` makes the `Hash` with all section keys and empty arrays.
2. `add_blocks` puts the Bluesky blocks into the correct sections.
3. `add_blocks` puts the Twitter blocks into the same sections.

`tap` gives back the `Hash`, and not the result of the last `add_blocks` call.

`index_with { [] }` in `empty_sections` runs the block one time for each key. Thus
each section gets its own array. A shared array would be a defect here.

## The date window

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

The window starts at 00:00 on the start date. It stops immediately before 00:00 on
the day after the end date. The three dots make the end exclusive. Therefore the
full end day is inside the window, but the next day is not.

Rails changes this Ruby range into a `BETWEEN`-type SQL condition on the timestamp
column.

## How the class reads the posts

`#bluesky_blocks` and `#twitter_blocks` have the same shape. Only the column names
and the model change:

| Step | Bluesky | Twitter |
|---|---|---|
| Association | `bluesky_posts` | `tweets` |
| Time column | `post_created_at` | `tweet_created_at` |
| Thread key | `thread_root_uri` or `uri` | `conversation_id` or `tweet_id` |
| Root identifier | `uri` | `tweet_id` |

Each method does five things:

1. It limits the records to the organisation of the edition.
2. It keeps only the records inside the window with `hidden: false`.
3. It removes the records that the user excluded (see below).
4. It preloads the associations that the views need.
5. It sorts the records by time and calls `to_a`.

The preload list stops N+1 queries:

```ruby
includes(:url_titles,
  author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS },
  snapshot_image_attachment: :blob)
```

The nested `author: { author: ... }` is correct. The first `author` is the platform
author, for example `Bluesky::Author`. The second `author` is the shared `Author`
record. `PLATFORM_ACCOUNT_ASSOCIATIONS` then loads the accounts of that person on
Twitter, Mastodon, Bluesky and dev.to. The views use these accounts to show links.

`to_a` runs the SQL query. All later work happens in Ruby memory.

## How the class makes the threads

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

The method is the same for the two platforms. The caller gives the differences as
arguments. `method(:bluesky_thread_key)` makes a callable object from a private
method. Therefore `build_blocks` does not need to know the platform.

The steps are:

1. `group_by` puts the records with the same thread key into one group.
2. `sort_by` puts each group into time order.
3. The `find` block looks for the record that is its own root. For Bluesky, the
   thread key is equal to the `uri` of the record. For Twitter, the thread key is
   equal to the `tweet_id`.
4. If the query found no root, the earliest record becomes the root. This occurs
   when the true root is outside the date window.
5. The other records become `thread_members`.
6. The blocks go into time order, by the timestamp of their root.

`root_identifier` gives back `nil` for a class that is not `Bluesky::Post` or
`Twitter::Tweet`. Then no record can be the root, and step 4 keeps the code safe.

## The thread keys

```ruby
post.thread_root_uri.presence || post.uri
tweet.conversation_id.presence || tweet.tweet_id
```

A post that is not part of a thread has no `thread_root_uri`. Then its own `uri`
becomes the key. Thus a single post makes a group of one record, and the code needs
no special case.

## How the class removes excluded posts

The user can hide a post from an edition. An `EditionExclusion` record holds this
choice. The association is polymorphic, so one table holds Bluesky posts and
tweets.

There are two levels of exclusion:

**Level 1 — one record.** `excluded_bluesky_ids` and `excluded_twitter_ids` give
the primary keys. `where.not(id: ...)` removes them. If a reply is excluded, only
that reply goes away. The thread stays.

**Level 2 — a full thread.** `excluded_bluesky_thread_roots` and
`excluded_twitter_thread_roots` keep only the excluded records that are the root of
their own thread:

```ruby
post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
```

If the excluded record is a thread root, the query removes every record of that
thread. Therefore, when the user hides the first post of a thread, the full thread
goes away.

The `without_*_root_exclusions` methods give back the scope with no change when the
list is empty. This stops an SQL condition that has no purpose.

`.then { |scope| ... }` keeps the conditional part inside the query chain. This is
better than a local variable and an `if` statement.

## Memoization

Four methods keep their result in an `@_` instance variable. But `excluded_records`
itself has no memoization. Thus the class makes two queries for each platform, and
four queries in total, for the exclusions. Each query loads the same rows. This is
a small cost, because the number of exclusions is low.

## Section mapping

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
next unless sections.key?(section_key)
```

Only the `section` value of the root post decides the section of the full block.
The replies follow their root.

`SectionTaxonomy.for` maps a post section, for example `'code'` or `'slides'`, onto
a newsletter section, for example `'code_and_ruby'` or `'videos'`. An unknown value
falls back to `'post'`, which maps onto `'code_and_ruby'`.

Because of that fallback, `SectionTaxonomy.for` always gives a key that is in
`ordered_top_level`. The `next unless sections.key?` line is protection only. It
does not operate with the taxonomy of today.

## Two points to know

**The order inside a section is per platform, and not per time.** `#call` adds all
Bluesky blocks first, then all Twitter blocks. `build_blocks` sorts inside one
platform only. There is no sort after the merge. Therefore a section shows the
Bluesky blocks in time order, and then the Twitter blocks in time order. A tweet
from Monday comes after a Bluesky post from Friday.

**All sorting happens in Ruby.** The SQL `ORDER BY` sets the input order, but
`build_blocks` sorts the groups and the blocks again in memory. The database order
is thus not important for the result. It is important only for stability when two
records have the same timestamp.

## Design notes

The class follows a clear pattern:

- `#call` is the only public method. All other methods are private.
- Each private method has one job and a name that says the job.
- The two platform methods are almost the same. The shared logic lives in
  `build_blocks`, and the differences pass as arguments.
- The class does no output work. It gives back plain data. The views, the Markdown
  writer and the summary job decide how to show the data.
