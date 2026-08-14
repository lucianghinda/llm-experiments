# How `Edition::DraftQuery` works

## What the class does

`Edition::DraftQuery` collects the social media posts for one newsletter edition.
It reads posts from two platforms. The platforms are Bluesky and Twitter.
It groups the posts into threads. It then sorts the threads into newsletter sections.

You give the class one `Edition`. You call `call`. You get back a Hash.
In that Hash, each key is a section name. Each value is an array of blocks.

## The block

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

A block is one item in the newsletter. It has two parts.
The `root` is the first post of a thread. The `thread_members` are the other posts of the same thread.
A single post that is not part of a thread becomes a block with an empty `thread_members` array.

`Data.define` makes a small, read-only value object. The block cannot change after you create it.

## The main method

```ruby
def call
  empty_sections.tap do |sections|
    add_blocks(sections, bluesky_blocks)
    add_blocks(sections, twitter_blocks)
  end
end
```

The method does three steps.

1. It makes an empty Hash with one key for each newsletter section.
2. It puts the Bluesky blocks into that Hash.
3. It puts the Twitter blocks into the same Hash.

`tap` returns the Hash after the two `add_blocks` calls change it.
The result always has all section keys. Some sections can hold an empty array.

## The empty sections

```ruby
Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
```

`ordered_top_level` returns the section keys in newsletter order.
The order starts with `launches` and ends with `related`.
`index_with { [] }` makes each key point to a new, empty array.

This step is important. It fixes the order of the sections one time, at the start.
The code that comes after it only appends to arrays. The section order never changes again.

## The date window

```ruby
def window
  edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
end
```

The window is a time range. It starts at midnight on the first day of the edition.
It ends at midnight on the day after the last day of the edition.

The range uses three dots. Three dots exclude the last value.
So a post at midnight on the day after the edition is not in the window.
A post late in the evening of the last day is in the window.
This is how the code includes the full last day and no more.

## The two query branches

The Bluesky branch and the Twitter branch are almost the same.
Only the column names and the model names are different.

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

Each line adds one filter or one instruction.

- `edition.organisation.bluesky_posts` limits the posts to the owner of the edition. Posts of other organisations never appear.
- `where(post_created_at: window, hidden: false)` keeps only posts inside the date window. It also removes posts that a person marked as hidden.
- `where.not(id: excluded_bluesky_ids)` removes the posts that a person excluded from this edition.
- `then { ... }` sends the query to a helper method. The helper adds one more filter, but only when it is necessary.
- `includes(...)` loads the related records in the same request. This prevents many small database requests later.
- `order(:post_created_at)` sorts the posts from old to new.
- `to_a` runs the query. All work after this line happens in memory.

The Twitter branch uses `tweets`, `tweet_created_at`, `excluded_twitter_ids` and `without_twitter_root_exclusions`.
Everything else is identical.

The `includes` call loads three things:

1. `url_titles`, which are the titles of the links in the post.
2. The author, and then the person behind that author, and then all platform accounts of that person.
3. The attached snapshot image and its blob.

The view needs all of this data. Without `includes`, the view would make one database request for each post.

## How the code finds threads

```ruby
def bluesky_thread_key(post)
  post.thread_root_uri.presence || post.uri
end

def twitter_thread_key(tweet)
  tweet.conversation_id.presence || tweet.tweet_id
end
```

Each post gets a thread key.
If the post belongs to a thread, the key is the identifier of the thread root.
If the post is alone, the key is the identifier of the post itself.
`presence` returns `nil` for an empty string, so an empty value falls back to the second option.

Posts of the same thread get the same key. This is what makes the grouping work.

## How the code builds the blocks

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

This method is generic. It works for both platforms.
The caller sends the records, the name of the timestamp column, and a method object for the thread key.
`method(:bluesky_thread_key)` wraps a private method into an object. The generic code can then call it with `call`.

The method does four steps.

1. `group_by` puts all posts with the same thread key into the same group.
2. `sort_by` puts the posts of each group in time order.
3. `find` looks for the true root of the thread. A post is the true root when its thread key is equal to its own identifier. If no post satisfies this test, the code uses the oldest post of the group.
4. `ordered_records - [root]` removes the root from the list. The rest become the thread members.

The last line sorts the blocks by the time of their root.

Step 3 has an important effect.
Sometimes the real root of a thread is outside the date window.
Then no post in the group is the true root. The oldest post in the window becomes the root of the block.
A single reply from an old thread can therefore appear alone in the newsletter.

```ruby
def root_identifier(record)
  case record
  when Bluesky::Post
    record.uri
  when Twitter::Tweet
    record.tweet_id
  end
end
```

This method gives the identity of one record. Bluesky uses a URI. Twitter uses a tweet identifier.
This is the only place where the generic code must know the model type.

## How the code puts blocks into sections

```ruby
def add_blocks(sections, blocks)
  blocks.each do |block|
    section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
    next unless sections.key?(section_key)

    sections.fetch(section_key) << block
  end
end
```

The section of the root decides the section of the whole block.
The thread members do not have a vote.

`SectionTaxonomy.for` translates the section of a post into a newsletter section.
For example, `library` becomes `libraries`, and `video` becomes `videos`.
If the section is empty or unknown, the taxonomy uses the default value `post`. That value maps to `code_and_ruby`.

`next unless sections.key?(section_key)` is a safety check. It protects the code against a section that has no place in the newsletter.

Note the order.
`call` adds all Bluesky blocks first, and then all Twitter blocks.
Inside one section, the Bluesky blocks come before the Twitter blocks.
The two platforms are not mixed by time.

## How the exclusions work

A person can hide a post from one edition. The app records this in an `EditionExclusion` row.
The row points to the edition and to the post. The link is polymorphic, so it can point to a Bluesky post or to a tweet.

```ruby
def excluded_records(model)
  edition.edition_exclusions.where(excludable_type: model.name).includes(:excludable).map(&:excludable)
end
```

This method loads the excluded posts of one type for this edition.

There are two levels of exclusion.

**Level one: the post itself.**

```ruby
def excluded_bluesky_ids
  @_excluded_bluesky_ids ||= excluded_records(Bluesky::Post).map(&:id)
end
```

The query removes these identifiers. This hides one post and nothing more.

**Level two: the whole thread.**

```ruby
def excluded_bluesky_thread_roots
  @_excluded_bluesky_thread_roots ||= excluded_records(Bluesky::Post).filter_map do |post|
    post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
  end
end
```

This method keeps only the excluded posts that are thread roots.
A post is a thread root when its `thread_root_uri` is equal to its own `uri`.

```ruby
def without_bluesky_root_exclusions(scope)
  return scope if excluded_bluesky_thread_roots.empty?

  scope.where.not(thread_root_uri: excluded_bluesky_thread_roots)
end
```

The query then removes every post that points to one of those roots.

The rule is simple.
If you hide a reply, only that reply disappears.
If you hide the first post of a thread, the whole thread disappears.

The guard clause is necessary. `where.not(column: [])` in SQL removes all rows.
Without the guard, an edition with no exclusions would return no posts at all.

The Twitter methods do the same work with `conversation_id` and `tweet_id`.

## Memoisation

The four exclusion methods use `@_name ||= ...`.
Ruby runs the code one time and stores the result. Later calls read the stored value.

This matters because `without_bluesky_root_exclusions` reads `excluded_bluesky_thread_roots` two times.
It reads it once in the guard clause and once in the `where.not` call.
Without memoisation, the code would send a second query to the database.

Note that `excluded_bluesky_ids` and `excluded_bluesky_thread_roots` are separate values.
Each one calls `excluded_records` one time. So the class sends two exclusion queries per platform, and four in total.

## The shape of the result

The method returns a Hash like this:

```ruby
{
  'launches'      => [DraftBlock, DraftBlock],
  'events'        => [],
  'code_and_ruby' => [DraftBlock],
  # ... all other sections, in newsletter order
}
```

Three callers use this result:

- `EditionsController#show` shows the draft in the browser.
- `Newsletter::EditionMarkdown` builds the Markdown file of the newsletter.
- `Newsletter::SummarizeEditionPostsJob` sends the posts to a summarizer.

Because the class always returns every section key, the callers do not need to check for a missing key.
They only need to check if an array is empty.

## Summary of the design

The class is a query object. It has one public method and no state that changes.

The work happens in four stages.

1. The database gives a flat list of visible posts, in time order.
2. `build_blocks` turns the flat list into threads.
3. `add_blocks` puts the threads into sections.
4. The result is a ready-to-render Hash.

The database does the filtering. Ruby does the grouping.
The two platform branches stay separate because their column names are different.
They join again in `build_blocks`, which is generic and works for both.
