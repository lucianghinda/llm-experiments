`Edition::DraftQuery` prepares social posts for one newsletter draft. It reads records. It does not change records.

### Input and output

The input is one `Edition` record.

The `call` method returns a `Hash`. The hash contains every newsletter section. Empty sections remain in the hash.

Each section contains `DraftBlock` objects. Each block has two fields:

- `root`: The main post.
- `thread_members`: The related posts in time order.

See [draft_query.rb](app/services/edition/draft_query.rb:3).

### Main process

1. The service creates the empty sections.
2. The service gets Bluesky posts.
3. The service gets Twitter posts.
4. The service groups related posts into threads.
5. The service puts each block in a newsletter section.
6. The service returns the sections.

The `tap` method returns the original sections hash after these changes.

### Date range

The range starts at `00:00` on the edition start date.

The range stops at `00:00` after the edition end date. Thus, the range includes the complete end date.

See [draft_query.rb](app/services/edition/draft_query.rb:25).

### Record selection

The service selects posts that meet these conditions:

- The post belongs to the edition organization.
- The post time is in the date range.
- The post is not hidden.
- The edition does not exclude the post.

The service loads related author, link, and image data at the same time. This operation prevents extra database requests during display.

The service does not select Mastodon posts.

### Thread groups

For Bluesky, `thread_root_uri` identifies a thread. A standalone post uses its own `uri`.

For Twitter, `conversation_id` identifies a thread. A standalone tweet uses its own `tweet_id`.

The service puts records with the same identifier into one group. It sorts each group by time.

The normal root is the record whose identifier matches the thread identifier. If that record is absent, the earliest available member becomes the root.

This fallback applies when the real root is outside the edition date range.

See [draft_query.rb](app/services/edition/draft_query.rb:57).

### Exclusions

An exclusion of one thread member removes only that member.

An exclusion of a thread root removes the complete thread. The service removes all records that have the excluded root identifier.

Only exclusions for the current edition apply.

See [draft_query.rb](app/services/edition/draft_query.rb:95).

### Newsletter sections

The section of the root controls the section of the complete block.

The taxonomy converts post sections such as `code` and `library` to newsletter sections. A missing or unknown section becomes `code_and_ruby`.

The service adds all Bluesky blocks first. It then adds all Twitter blocks. Therefore, it does not combine both platforms into one time order.

The dedicated test file confirms these rules: [draft_query_test.rb](test/services/edition/draft_query_test.rb:5).