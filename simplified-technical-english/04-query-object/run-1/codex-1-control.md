`Edition::DraftQuery` builds the newsletter’s draft content for one edition. It returns an ordered hash of newsletter sections, where each section contains grouped Bluesky and Twitter/X threads.

The main flow is in [`call`](app/services/edition/draft_query.rb:10):

1. Create every top-level newsletter section with an empty array.
2. Fetch and group eligible Bluesky posts.
3. Fetch and group eligible tweets.
4. Add each resulting thread block to the section determined by its root post.

A simplified output looks like:

```ruby
{
  "articles" => [
    DraftBlock.new(root: post, thread_members: [reply_1, reply_2])
  ],
  "news" => [],
  # ...
}
```

### Selecting records

The `window` method creates a half-open date range:

```ruby
edition.start_date.beginning_of_day...
edition.end_date.tomorrow.beginning_of_day
```

That includes the entirety of both the edition’s start and end dates.

For each platform, the query starts from the edition organisation’s posts or tweets and keeps records that:

- Were created inside the edition window.
- Are not hidden.
- Have not been individually excluded.
- Do not belong to a thread whose root was excluded.

It then eager-loads URL titles, author/platform-account data, and snapshot images to avoid later N+1 queries.

### Grouping posts into threads

[`build_blocks`](app/services/edition/draft_query.rb:57) groups records by their thread identity:

- Bluesky: `thread_root_uri`, falling back to the post’s own URI.
- Twitter: `conversation_id`, falling back to the tweet’s own ID.

Within each group it:

1. Sorts records chronologically.
2. Looks for the actual root record.
3. Falls back to the earliest available record if the true root is unavailable—for example, outside the date window.
4. Produces a `DraftBlock` containing the root and the remaining thread members.
5. Sorts all blocks by their root timestamps.

`DraftBlock` is a small read-only value object defined at [line 4](app/services/edition/draft_query.rb:4).

### Exclusion behavior

Exclusions have two levels:

- Excluding a reply removes only that individual record.
- Excluding a record identified as the thread root removes the entire thread by filtering every record carrying that root URI or conversation ID.

The exclusion records are loaded separately for Bluesky and Twitter and memoized so they are calculated only once per query object.

### Assigning newsletter sections

[`add_blocks`](app/services/edition/draft_query.rb:78) translates the root post’s `section` through `Newsletter::SectionTaxonomy`, then appends the block to the corresponding top-level section. Blocks resolving to something outside the initialized top-level sections are skipped.

One subtle ordering detail: blocks are chronological within each platform, but Bluesky blocks are appended before all Twitter blocks. Therefore a section containing both platforms is not globally chronological.