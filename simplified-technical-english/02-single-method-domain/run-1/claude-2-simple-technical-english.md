# How `build_blocks` works

## Purpose

The method lives in `app/services/edition/draft_query.rb`.

The class builds the draft of a newsletter edition. The draft contains social media posts. Some posts stand alone. Other posts belong to a thread. A thread is one post plus its replies from the same author.

The newsletter must show a thread as one item, not as many separate items. `build_blocks` does that work. It takes a flat list of records and returns a list of blocks. Each block is one thread.

## The method

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

## The three inputs

| Input | Type | Function |
| --- | --- | --- |
| `records` | Array of models | The posts that passed the filters. They are already loaded from the database. |
| `timestamp_method` | Symbol | The name of the time attribute. The method uses it to sort. |
| `thread_key` | Method object | A function that returns the thread identity of one record. |

The method knows nothing about Bluesky and nothing about Twitter. The caller supplies the platform knowledge. Therefore one method serves two platforms.

## What the two callers pass

| Caller | `timestamp_method` | `thread_key` returns |
| --- | --- | --- |
| `bluesky_blocks` | `:post_created_at` | `post.thread_root_uri` if it is present, else `post.uri` |
| `twitter_blocks` | `:tweet_created_at` | `tweet.conversation_id` if it is present, else `tweet.tweet_id` |

Both platforms store a pointer to the first post of the thread. Bluesky calls it `thread_root_uri`. Twitter calls it `conversation_id`. Both columns can be empty. In that case the fallback is the identity of the record itself. A record with no thread is then a thread of one member.

## Step 1: Group the records into threads

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`group_by` puts every record in a bucket. The bucket name is the thread key. All members of one thread share the same key. `.values` drops the names and keeps the buckets.

The result is an array of arrays. Each inner array is one thread.

This step runs in Ruby memory. It does not run in SQL. The caller already called `to_a` on the query.

## Step 2: Sort the members of the thread by time

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

The records inside one thread go in chronological order. The oldest record comes first.

## Step 3: Find the root record

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end || ordered_records.first
```

The root is the first post of the thread. The replies point to it.

`root_identifier` returns the own identity of a record:

```ruby
def root_identifier(record)
  case record
  when Bluesky::Post then record.uri
  when Twitter::Tweet then record.tweet_id
  end
end
```

The test is one comparison. A record is the root when its thread key is equal to its own identity. In other words, the post points to itself as the start of the thread. A reply points to a different post, so the two values are different.

The `||` operator supplies a fallback. If no record passes the test, the method takes the oldest record of the group.

The fallback is necessary. The real root can be absent from `records`. Three situations cause this:

1. The root is outside the date window of the edition.
2. The root has the flag `hidden` set to true.
3. An editor excluded the root from this edition.

Without the fallback, `root` would be `nil` and the next lines would fail.

## Step 4: Build one block

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a `Data` object with two fields. The class defines it at the top of the file:

```ruby
DraftBlock = Data.define(:root, :thread_members)
```

The field `root` holds the main post. The field `thread_members` holds the other posts. The expression `ordered_records - [root]` removes the root from the ordered list. The remaining records keep the chronological order.

A single post produces a block with a root and an empty `thread_members` array.

## Step 5: Sort the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

The method now has one block per thread. It sorts the blocks by the time of the root post.

`public_send` calls the attribute by name, because the name comes from the argument. The method cannot write `block.root.post_created_at`, because the attribute name is different for the two platforms.

The result is a chronological list of threads.

## What happens after this method

The caller `call` puts the blocks into sections:

```ruby
def add_blocks(sections, blocks)
  blocks.each do |block|
    section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
    next unless sections.key?(section_key)

    sections.fetch(section_key) << block
  end
end
```

The section comes from `block.root.section`. Only the root decides the section. The replies follow the root, also when their own section value is different.

## Points to know

- The method is pure. It reads no database and it changes no record. It only transforms an array.
- The grouping happens in memory. The cost grows with the number of records in the date window.
- The sort in step 2 and the sort in step 5 are stable in Ruby only for equal keys inside one list. Two posts with the same timestamp keep the order that `group_by` gave them.
- The method trusts the filters of the caller. A hidden post or an excluded post never arrives here.
- `ordered_records - [root]` compares with `==`. Active Record objects of the same class and the same `id` are equal. All records here are persisted, so the subtraction removes exactly one record.
