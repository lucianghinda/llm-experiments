[`Edition::DraftQuery`](app/services/edition/draft_query.rb:3) prepares social posts for an edition’s newsletter draft.

In simple terms, it:

1. Creates an empty list for every newsletter section.
2. Finds relevant Bluesky posts and Twitter tweets.
3. Groups posts belonging to the same thread.
4. Places each thread into the correct newsletter section.
5. Returns all sections and their draft content.

### Input and output

It receives one `Edition`:

```ruby
query = Edition::DraftQuery.new(edition)
sections = query.call
```

The result is shaped roughly like:

```ruby
{
  "launches" => [draft_block, draft_block],
  "events" => [],
  "code_and_ruby" => [draft_block]
}
```

Every `DraftBlock` contains:

```ruby
DraftBlock.new(
  root: main_post,
  thread_members: replies
)
```

### How it selects posts

For both Bluesky and Twitter, it selects posts that:

- Belong to the edition’s organisation.
- Were published between the edition’s start and end dates.
- Are not hidden.
- Have not been excluded from this edition.

The date range includes the entire start and end days. For example, an edition from August 1 to August 3 includes everything from the beginning of August 1 until just before August 4.

The `includes(...)` calls preload authors, URL titles, and snapshot images. This avoids many extra database queries when the draft is displayed later.

### How thread grouping works

Posts are grouped using their platform’s thread identifier:

- Bluesky uses `thread_root_uri`; standalone posts use their own `uri`.
- Twitter uses `conversation_id`; standalone tweets use their own `tweet_id`.

Inside each group, the query:

- Sorts posts by publication time.
- Finds the real thread root.
- Uses the earliest available post if the real root is unavailable.
- Stores every other post as a thread member.

Finally, it sorts the completed blocks by the root post’s publication time.

### How exclusions work

There are two important cases:

- Excluding a reply removes only that reply.
- Excluding a thread’s root removes the entire thread.

The exclusion records use a polymorphic association, so the same mechanism supports both `Bluesky::Post` and `Twitter::Tweet`.

### How sections are assigned

The root post’s `section` determines where the whole block goes:

```ruby
section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
```

The taxonomy converts the post’s section into a top-level newsletter section. If that section is not present in the prepared section list, the block is skipped.

One subtle detail: Bluesky blocks are added before Twitter blocks. Each platform is sorted internally, but the final section is not re-sorted across both platforms. Therefore, a newer Bluesky block can appear before an older Twitter block.