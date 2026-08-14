[`build_blocks`](app/services/edition/draft_query.rb:57) makes an ordered list of social-media thread blocks.

It uses three inputs:

- `records` is a list of posts or tweets.
- `timestamp_method` gives the creation time of a record.
- `thread_key` gives the thread identifier of a record.

The method does these operations:

1. It groups records that have the same thread identifier.
2. It sorts each group by creation time.
3. It searches each group for the thread root.
4. The root identifier is `uri` for a Bluesky post.
5. The root identifier is `tweet_id` for a Twitter tweet.
6. If the method cannot find the real root, it uses the earliest record.
7. It makes one `DraftBlock` for each group.
8. The block contains the root and the other records.
9. The other records stay in time order.
10. It sorts all blocks by the creation time of their roots.
11. It returns the sorted blocks.

Thus, each result has this form:

```ruby
DraftBlock.new(
  root: root_record,
  thread_members: other_records
)
```

For Bluesky, the method uses `post_created_at` and the Bluesky thread key. For Twitter, it uses `tweet_created_at` and the Twitter conversation key.