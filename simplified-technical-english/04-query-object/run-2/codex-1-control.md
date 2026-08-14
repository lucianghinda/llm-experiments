[`Edition::DraftQuery`](app/services/edition/draft_query.rb:3) prepares the social posts used to build an edition draft.

Its output is an ordered hash shaped roughly like:

```ruby
{
  section_key => [
    DraftBlock.new(
      root: post_or_tweet,
      thread_members: [reply, reply]
    )
  ]
}
```

How it works:

1. `call` creates every top-level newsletter section with an empty array, then adds Bluesky blocks followed by Twitter blocks.

2. It selects posts belonging to the edition’s organisation whose platform timestamp falls anywhere from the beginning of `start_date` through the end of `end_date`. The half-open range ending at midnight on the following day makes the edition’s final date inclusive.

3. It filters out:

   - hidden records;
   - records explicitly listed in the edition’s polymorphic `edition_exclusions`;
   - an entire conversation when its actual root post has been excluded.

   Excluding a reply removes only that reply. Excluding a root removes the root and records whose `thread_root_uri` or `conversation_id` points to it.

4. It eager-loads URL titles, author/platform accounts, and snapshot images. This makes the returned objects ready for rendering without generating many additional database queries.

5. `build_blocks` reconstructs conversations:

   - Bluesky records group by `thread_root_uri`, falling back to their own `uri`.
   - Twitter records group by `conversation_id`, falling back to their own `tweet_id`.
   - Records inside each conversation are ordered chronologically.
   - The service finds the record whose own identifier matches the conversation identifier and uses it as the root.
   - If the true root isn’t in the result—perhaps because it is outside the edition window—the earliest available member becomes the effective root.
   - Everything else becomes `thread_members`.

6. Each block is placed into the newsletter section determined by its root’s `section`. A block is discarded if that mapped section isn’t one of the configured top-level sections.

A notable ordering detail: Bluesky blocks are appended before Twitter blocks. Each platform is chronological internally, but the final contents of a section are not globally interleaved by timestamp across both platforms.

The resulting structure is consumed by the edition page, the Markdown newsletter generator, and the job that schedules post summaries.