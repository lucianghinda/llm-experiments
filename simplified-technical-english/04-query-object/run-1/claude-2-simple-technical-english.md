# How Edition::DraftQuery works

## Purpose

The file `app/services/edition/draft_query.rb` builds the draft of one newsletter edition.

An edition has a start date and an end date. In that time range the organisation collected posts from Bluesky and tweets from Twitter. The editor must see this material grouped in newsletter sections, in the correct order, without the items that the editor removed.

The class does that work. It reads the database one time per platform and returns a plain data structure. It writes nothing.

## The public interface

The class has one public method:

```ruby
Edition::DraftQuery.new(edition).call
```

The result is a Hash. The keys are the newsletter section keys. The values are arrays of blocks.

```
{
  "launches"      => [block, block],
  "events"        => [],
  "code_and_ruby" => [block],
  ...
}
```

Three places call this method:

| Caller | Use |
| --- | --- |
| `EditionsController#show` | Renders the draft page in the browser. |
| `Newsletter::EditionMarkdown` | Exports the draft as a Markdown file. |
| `Newsletter::SummarizeEditionPostsJob` | Sends each post to the summarizer. |

All three get the same structure. The rule about what belongs in an edition lives in one file only.

## The block

The first line of the class defines the unit of output:

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

`Data.define` makes a small immutable value object. A block has one root record and a list of thread members.

A block is one item in the newsletter. If an author wrote a single post, the block has that post as root and an empty member list. If an author wrote a thread of four posts, the block has the first post as root and the other three as members.

The consumers of this class treat a block as one entry with one heading and one link.

## Step 1: Build the empty sections

```ruby
def empty_sections
  Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
end
```

`Newsletter::SectionTaxonomy` holds the list of the 11 newsletter sections. Each section has a key, an emoji, a heading, and an order number. `ordered_top_level` returns the keys sorted by that order number.

`index_with` turns the array of keys into a Hash. The block gives each key a new empty array.

Two effects come from this line:

1. The output always contains all 11 sections. A section with no content is present with an empty array. The caller does not need to check for a missing key.
2. The Hash keys keep the taxonomy order. Ruby hashes keep insertion order. The newsletter sections therefore appear in the correct sequence without extra sort work later.

`call` uses `tap` to fill this Hash:

```ruby
def call
  empty_sections.tap do |sections|
    add_blocks(sections, bluesky_blocks)
    add_blocks(sections, twitter_blocks)
  end
end
```

`tap` runs the block and returns the original object. The method reads as a short summary of the whole class. Make the empty sections. Add the Bluesky blocks. Add the Twitter blocks. Return the sections.

Note the order. Bluesky blocks enter a section before Twitter blocks. Inside one section the Bluesky items come first, then the Twitter items. Each group is sorted by time, but the two groups are not merged into one time line.

## Step 2: Define the time window

```ruby
def window
  edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
end
```

The edition stores dates. The posts store timestamps. The method converts the dates into a range of timestamps.

- The range starts at 00:00:00 on the start date.
- The range ends at 00:00:00 on the day after the end date.
- The range uses three dots. Three dots exclude the last value.

The result is a window that contains the complete end date and nothing of the next day. A post at 23:59 on the end date is inside. A post at 00:00 on the next day is outside.

Rails converts this Ruby range into a `BETWEEN` style SQL condition with an exclusive upper bound.

## Step 3: Load the records

The two loader methods have the same shape. Only the column names change.

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

The chain does six things:

| Part | Function |
| --- | --- |
| `edition.organisation.bluesky_posts` | Limits the query to the owner of the edition. |
| `where(post_created_at: window, hidden: false)` | Applies the time window and skips globally hidden posts. |
| `where.not(id: excluded_bluesky_ids)` | Skips the posts that the editor removed from this edition. |
| `then { ... }` | Adds the thread level exclusion, but only when one exists. |
| `includes(...)` | Loads the associations in advance. |
| `order(...)` then `to_a` | Sorts by time and runs the query one time. |

Three details are important here.

**`then` keeps the chain flat.** A relation chain cannot hold an `if` statement. `Object#then` passes the current scope into a method and takes the new scope back. The method can decide to add a condition or to return the scope without a change.

**`includes` prevents the N+1 problem.** The draft page shows the author name, the author link, and the snapshot image of every record. Without `includes`, each record triggers new queries during rendering. The test file asserts this. It walks over all the loaded records, touches those associations, and requires a query count of zero.

**`to_a` ends the lazy chain.** After this call the code works with plain Ruby arrays. The grouping work that follows happens in memory.

The Twitter method is the mirror image. It uses `tweets`, `tweet_created_at`, `excluded_twitter_ids`, and `without_twitter_root_exclusions`.

Mastodon posts are not in this class. The organisation has them, but the newsletter draft ignores them.

## Step 4: Group the records into blocks

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

This method is shared by both platforms. The caller passes the platform difference as arguments:

```ruby
build_blocks(records, :post_created_at, method(:bluesky_thread_key))
```

`method(:bluesky_thread_key)` makes a callable object from a private method. The generic code calls it with `thread_key.call(record)` and stays free of platform knowledge.

The method has four operations.

### 4.1 Group by thread key

```ruby
def bluesky_thread_key(post)
  post.thread_root_uri.presence || post.uri
end

def twitter_thread_key(tweet)
  tweet.conversation_id.presence || tweet.tweet_id
end
```

Each platform marks a thread with an identifier of the first item. Bluesky uses `thread_root_uri`. Twitter uses `conversation_id`.

If the field is empty, the record is not part of a thread. The method then uses the own identifier of the record. That value is unique, so the record forms a group of one.

After `group_by`, all records of one thread sit in one array.

### 4.2 Sort each group by time

`sort_by(&timestamp_method)` puts the posts of a thread in the order that the author wrote them. The reader of the newsletter sees the thread in the correct sequence.

### 4.3 Find the root

```ruby
root = ordered_records.find { |record| thread_key.call(record) == root_identifier(record) } ||
       ordered_records.first
```

A record is the root of its thread when the thread identifier equals its own identifier. `root_identifier` returns the own identifier:

```ruby
def root_identifier(record)
  case record
  when Bluesky::Post then record.uri
  when Twitter::Tweet then record.tweet_id
  end
end
```

The `||` is a fallback. It covers a real case. An author starts a thread on Monday and adds a reply on Wednesday. The edition covers Wednesday only. The window then loads the reply without the first post. No record in the group is a true root. The fallback makes the earliest available record the root of the block.

The test suite calls this case the orphan member. The result is a normal block with an empty member list.

### 4.4 Sort the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

`group_by` returns the groups in first appearance order. That order is not reliable after grouping. The final sort puts the blocks in the order of their root timestamps.

## Step 5: Put each block in a section

```ruby
def add_blocks(sections, blocks)
  blocks.each do |block|
    section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
    next unless sections.key?(section_key)

    sections.fetch(section_key) << block
  end
end
```

Every post has a `section` column with a content type such as `article`, `library`, or `video`. The taxonomy maps that content type to a newsletter section.

The mapping is not one to one. `post` and `code` both map to `code_and_ruby`. `video` and `slides` both map to `videos`. An unknown value or a `nil` value falls back to the default `post`, which also means `code_and_ruby`.

Only the section of the root decides. A thread lands in one section, even when the replies carry a different content type.

The line `next unless sections.key?(section_key)` is a safety check. The taxonomy always returns a valid top level key today, so the check never fails. It protects the code if somebody adds a mapping to a section that is not in the top level list.

## Step 6: The two levels of exclusion

An editor removes an item from an edition. The application stores that action in the `edition_exclusions` table. The record is polymorphic, so one table holds exclusions for both platforms.

```ruby
def excluded_records(model)
  edition.edition_exclusions.where(excludable_type: model.name).
    includes(:excludable).map(&:excludable)
end
```

The method loads the excluded records, not only their identifiers. The reason appears in the next step. The code must read the thread fields of those records.

The exclusion works on two levels.

### Level 1: One record

```ruby
def excluded_bluesky_ids
  @_excluded_bluesky_ids ||= excluded_records(Bluesky::Post).map(&:id)
end
```

The identifiers go into `where.not(id: ...)`. This removes exactly that record. If the record is a reply inside a thread, the rest of the thread stays.

### Level 2: A whole thread

```ruby
def excluded_bluesky_thread_roots
  @_excluded_bluesky_thread_roots ||= excluded_records(Bluesky::Post).filter_map do |post|
    post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
  end
end
```

`filter_map` keeps only the excluded records that are thread roots. The condition is the same test as in step 4.3.

Those root identifiers go into a second condition:

```ruby
def without_bluesky_root_exclusions(scope)
  return scope if excluded_bluesky_thread_roots.empty?

  scope.where.not(thread_root_uri: excluded_bluesky_thread_roots)
end
```

Now every post that points at that root disappears, not only the root itself.

The rule is easy to state. Hide the head of a thread and the whole thread goes away. Hide a reply and only that reply goes away. The tests state both rules directly.

The guard clause returns early on an empty list. Rails handles an empty array in `where.not` without an error, so the guard is about clarity more than about correctness.

### Two different meanings of hidden

The class uses two mechanisms with different scope:

| Mechanism | Scope |
| --- | --- |
| `hidden: false` column | Global. The post is hidden everywhere in the application. |
| `edition_exclusions` row | Local. The post is hidden in this edition only. |

The test confirms the second one. An exclusion that belongs to a different edition does not hide the post here.

## Memoization

Four methods cache their result in an instance variable with the `@_name ||=` pattern. The underscore prefix marks the variable as internal.

The cache is necessary because the loader methods use these values inside a query chain. Without the cache the same query would run again for each use.

One observation. `excluded_records` itself is not memoized. `excluded_bluesky_ids` and `excluded_bluesky_thread_roots` each call it one time. The same is true for the Twitter pair. The class therefore makes four exclusion queries instead of two. The cost is small because the number of exclusions per edition is small.

## Full flow

1. Make a Hash with all 11 section keys and empty arrays.
2. Compute the timestamp window from the edition dates.
3. Load the exclusion records for Bluesky and cache the identifiers and the excluded thread roots.
4. Load the Bluesky posts of the organisation inside the window, without hidden posts, without excluded posts, without posts of excluded threads, with the associations preloaded.
5. Group those posts by thread, order each thread, choose a root, and build one block per thread.
6. Sort the blocks by root time.
7. Repeat steps 3 to 6 for Twitter.
8. Put each block in the section of its root. Bluesky first, then Twitter.
9. Return the Hash.

## Design notes

**The class is a query object.** It takes one input in the constructor, exposes one verb as a public method, and keeps everything else private. It performs no writes and holds no state between calls.

**The private section is indented.** The methods after `private` sit at a deeper indentation level. This is a style rule from the Rubocop configuration of this codebase. It makes the visibility boundary visible.

**Platform differences are parameters.** `build_blocks` has no knowledge of Bluesky or Twitter. It receives a timestamp method name and a callable thread key. Only `root_identifier` still uses a `case` on the class, because it needs the class to choose the identifier column.

**The result is data, not objects with behaviour.** The output is a Hash of arrays of `Data` structs. The view, the Markdown exporter, and the background job each apply their own behaviour to the same data.

## Points to know

- The order inside a section is Bluesky blocks by time, then Twitter blocks by time. It is not one merged time line.
- The section of the root decides for the whole thread.
- A post with no `section` value goes to `code_and_ruby` through the default of the taxonomy.
- Mastodon content never appears in the draft.
- A thread member without its root in the window becomes a block of its own.
- The grouping work happens in Ruby, not in SQL. This is acceptable while one edition covers about one week of posts.
