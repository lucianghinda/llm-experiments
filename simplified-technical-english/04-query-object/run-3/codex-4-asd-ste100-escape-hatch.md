[Edition::DraftQuery](<app-root>/app/services/edition/draft_query.rb:3) builds the newsletter draft for one edition. It collects Bluesky posts and Twitter tweets, groups threads, and puts each result into a newsletter section.

### Return value

`call` returns an ordered hash:

```ruby
{
  "launches"      => [DraftBlock, ...],
  "events"        => [DraftBlock, ...],
  "code_and_ruby" => [DraftBlock, ...],
  # ...
}
```

Each `DraftBlock` contains:

- `root`: The main post that the newsletter displays.
- `thread_members`: The remaining posts in that thread, in time order.

### Processing flow

1. `empty_sections` creates all newsletter sections in their standard order. Every section exists in the result, even when it is empty.

2. `window` creates a half-open time range:

   ```ruby
   start_date at 00:00 ... day after end_date at 00:00
   ```

   Thus, the query includes the full start date and full end date. It excludes the first instant of the next day.

3. `bluesky_blocks` and `twitter_blocks` load records for the edition’s organisation. Each query:

   - Keeps records inside the time window.
   - keeps records where `hidden` is `false`.
   - removes edition exclusions.
   - loads related URL titles, authors, platform accounts, and snapshot images in advance.
   - sorts records by their platform timestamp.

   The advance loading prevents extra database queries when the view displays these records.

4. `build_blocks` groups records into threads:

   - Bluesky uses `thread_root_uri`. It uses the post `uri` when no thread root exists.
   - Twitter uses `conversation_id`. It uses `tweet_id` when no conversation ID exists.

5. For each group, the service finds the real thread root. A record is the root when its thread key equals its own platform identifier. If the real root is not present, the earliest available record becomes the root. This can occur when the real root is outside the edition date range.

6. `add_blocks` maps the root post’s `section` value to a newsletter section. A missing or unknown post section becomes `code_and_ruby` through `Newsletter::SectionTaxonomy`.

### Exclusion rules

The service reads polymorphic `EditionExclusion` records for this edition:

- If an exclusion targets one thread member, only that member is removed.
- If an exclusion targets a self-identified thread root, the root and all its thread members are removed.
- An exclusion from another edition has no effect.

### Important ordering detail

Thread members are in time order. Blocks from each platform are also in time order. However, the combined section is not in global time order: the service adds all Bluesky blocks first and all Twitter blocks second.

The service does not include Mastodon posts. The related [service tests](<app-root>/test/services/edition/draft_query_test.rb:5) specify these boundary, thread, exclusion, section, and eager-loading rules.