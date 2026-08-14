[`Edition::DraftQuery`](app/services/edition/draft_query.rb:3) builds the social-media content for an edition draft.

It returns an ordered hash shaped roughly like this:

```ruby
{
  news: [DraftBlock, DraftBlock],
  tutorials: [DraftBlock],
  tools: []
}
```

Each `DraftBlock` contains:

```ruby
DraftBlock.new(
  root: first_post,
  thread_members: [reply_1, reply_2]
)
```

How it works:

1. It creates an empty array for every top-level newsletter section.
2. It finds eligible Bluesky posts and Twitter tweets belonging to the edition’s organisation.
3. A post is eligible when it:

   - Was published between the edition’s start and end dates.
   - Is not hidden.
   - Has not been excluded from this edition.

4. If an excluded post is the root of a thread, the entire thread is excluded. Excluding a normal reply removes only that reply.
5. It groups posts into threads:

   - Bluesky uses `thread_root_uri`, falling back to the post’s own `uri`.
   - Twitter uses `conversation_id`, falling back to the tweet’s own ID.

6. Inside each thread, it:

   - Sorts posts by publication time.
   - Finds the root post.
   - Uses the earliest available post if the real root is missing.
   - Stores the remaining posts as `thread_members`.

7. It assigns the complete thread to the newsletter section selected by the root post.
8. Unknown or non-top-level sections are skipped.

The database queries also preload authors, links, and snapshot images. This avoids making many additional database queries when the draft is rendered.

One important ordering detail: Bluesky blocks are added before Twitter blocks. Each platform is chronological internally, but the final section does not combine both platforms into one globally chronological list.