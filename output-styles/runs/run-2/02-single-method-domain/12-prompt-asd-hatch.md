No MCP `rails_*` tools are connected in this session, so I read the file directly — and the request named the file and method explicitly.

## `build_blocks` — app/services/edition/draft_query.rb:57

The method makes a list of `DraftBlock` records. One block is one thread. Both `bluesky_blocks` (line 40) and `twitter_blocks` (line 54) call this method. The method is generic, so it takes the platform-specific parts as arguments.

### The three arguments

| Argument | Type | Function |
|---|---|---|
| `records` | Array | The posts or tweets in the date window. |
| `timestamp_method` | Symbol | The name of the time column: `:post_created_at` or `:tweet_created_at`. |
| `thread_key` | Method object | A function that gives the thread ID of one record. |

The `thread_key` function comes from `bluesky_thread_key` (line 87) or `twitter_thread_key` (line 91). Each one gives the thread root ID. If the record has no thread root ID, the function gives the ID of the record itself. Thus a single post that is not in a thread is its own thread.

### Step 1 — Group the records into threads

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`group_by` makes a Hash. The keys are the thread IDs. The values are arrays of records. `.values` removes the keys, because the code needs only the groups.

### Step 2 — Sort each group by time

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

The records in one thread go into chronological order. The `&` operator changes the Symbol into a block.

### Step 3 — Find the root record

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end || ordered_records.first
```

`root_identifier` (line 69) gives the own ID of the record: `uri` for a Bluesky post, `tweet_id` for a tweet. The thread key of the root record is equal to its own ID. Therefore the comparison is true only for the first post of the thread.

If the thread root is not in the list, `find` gives `nil`. This occurs when the root is hidden, or when the root is outside the date window. In this condition, the `||` operator selects the oldest available record as the root.

### Step 4 — Make the block

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a `Data` class (line 4). The `-` operator removes the root from the list. Thus `thread_members` contains the replies only, in chronological order.

### Step 5 — Sort the blocks

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

The blocks go into chronological order. The sort uses the time of the root record, not the time of the last reply. `public_send` is necessary here because `timestamp_method` is a Symbol, and the column name is different for each platform.

### Result

The method gives an array of `DraftBlock` records in chronological order. Each block has one root and its replies. Then `add_blocks` (line 78) puts each block into a newsletter section. The section comes from the `section` attribute of the root record.
