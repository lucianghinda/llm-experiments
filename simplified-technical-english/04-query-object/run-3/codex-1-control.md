[`Edition::DraftQuery`](<app-root>/app/services/edition/draft_query.rb:3) is a read-only assembler for a newsletter draft. Given an `Edition`, it returns:

```ruby
{
  "launches"      => [DraftBlock, ...],
  "events"        => [DraftBlock, ...],
  "code_and_ruby" => [DraftBlock, ...],
  # ...
}
```

Every `DraftBlock` contains:

```ruby
DraftBlock.new(
  root: root_post,
  thread_members: [reply_1, reply_2]
)
```

### How `call` works

1. [`empty_sections`](<app-root>/app/services/edition/draft_query.rb:21) creates every newsletter section, in taxonomy order, with an empty array. Empty sections therefore remain in the result.

2. [`window`](<app-root>/app/services/edition/draft_query.rb:25) creates a half-open date range:

   ```ruby
   start_date at 00:00 ... day after end_date at 00:00
   ```

   This includes the complete start and end dates while cleanly excluding the following day.

3. [`bluesky_blocks`](<app-root>/app/services/edition/draft_query.rb:29) and [`twitter_blocks`](<app-root>/app/services/edition/draft_query.rb:43) independently fetch posts that:

   - Belong to the edition’s organisation.
   - Were created inside the edition window.
   - Are not hidden.
   - Were not explicitly excluded from this edition.
   - Do not belong to a thread whose root was excluded.

   They also eager-load authors, URL titles, and snapshot images because draft rendering uses those associations.

4. [`build_blocks`](<app-root>/app/services/edition/draft_query.rb:57) groups records into threads:

   - Bluesky uses `thread_root_uri`, falling back to the post’s own `uri`.
   - Twitter uses `conversation_id`, falling back to the tweet’s own `tweet_id`.
   - Records inside a thread are sorted chronologically.
   - The record whose own identifier matches the thread identifier becomes the root.
   - If the real root is missing—perhaps outside the edition window—the earliest available member becomes the displayed root.

5. [`add_blocks`](<app-root>/app/services/edition/draft_query.rb:78) maps each block into a newsletter section based on the root post’s `section`. Unknown or `nil` post sections fall back through the taxonomy to `code_and_ruby`.

### Exclusion behavior

Exclusions are polymorphic `EditionExclusion` records:

- Excluding an ordinary thread member removes only that member.
- Excluding the thread root removes the entire thread.
- Exclusions belonging to another edition have no effect.

### Details worth noticing

- Mastodon posts are deliberately ignored.
- Blocks are chronologically ordered within each platform, but the combined section is not globally chronological: Bluesky blocks are appended first, followed by Twitter blocks.
- Because `where.not(thread_root_uri: ...)` and its Twitter equivalent operate on nullable columns, SQL `NULL` semantics may also omit standalone records with no thread identifier whenever a root exclusion exists. That is a potential edge case worth reviewing.

The file passes `ruby -c` syntax validation. Its focused test suite could not run because PostgreSQL was unavailable at `/tmp/.s.PGSQL.5432`.