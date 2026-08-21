# Edition::DraftQuery

File: `app/services/edition/draft_query.rb`

## 1. Function of the class

`Edition::DraftQuery` collects the social posts of one newsletter edition.
It puts these posts into newsletter sections.
It also puts the posts of one thread into one group.

The class only reads data. No method writes to the database.

## 2. How to use the class

The class has two public parts:

- `new(edition)` keeps the `Edition` record in the variable `@edition`.
- `call` does the work and gives the result.

Three parts of the application use the class:

- `EditionsController#show`
- `Newsletter::EditionMarkdown`
- `Newsletter::SummarizeEditionPostsJob`

## 3. The result

`call` gives a Hash.

- Each key is a newsletter section key, for example `'launches'`.
- Each value is an Array of `DraftBlock` objects.

The Hash contains all top-level sections.
A section with no content keeps an empty Array.
`Newsletter::SectionTaxonomy.ordered_top_level` sets the sequence of the keys.

## 4. The DraftBlock

`DraftBlock` is a `Data` class with two fields:

- `root` is the first post of a thread.
- `thread_members` is an Array with the other posts of the same thread.

For a single post, `thread_members` is empty.

## 5. The three steps in `call`

1. `empty_sections` makes the Hash. Each section key gets an empty Array.
2. `add_blocks` puts the Bluesky blocks into the Hash.
3. `add_blocks` puts the Twitter blocks into the Hash.

`tap` gives the same Hash back after the two `add_blocks` calls.
In each section, the Bluesky blocks come before the Twitter blocks.

## 6. The date window

The `window` method makes this Range:

```ruby
edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
```

The Range has three dots. Thus the Range does not contain the last value.

- The window starts at 00:00 on the start date.
- The window stops immediately before 00:00 on the day after the end date.
- The window contains the full end date.

## 7. The two database queries

`bluesky_blocks` and `twitter_blocks` have the same structure.
Each method reads the records of one platform for the organisation of the edition.

Each query does these operations:

1. It starts from `organisation.bluesky_posts` or from `organisation.tweets`.
2. It keeps only the records with a time in the window.
3. It keeps only the records with `hidden` equal to `false`.
4. It removes the records that the user excluded. See section 10.
5. It removes the threads that the user excluded. See section 10.
6. It loads the related data in advance with `includes`.
7. It puts the records in order of time.
8. It makes an Array with `to_a`.

Step 6 loads `url_titles`, the author with the platform accounts, and the
snapshot image with its blob. This prevents N+1 queries in the views.

The two platforms use different column names:

| Item | `Bluesky::Post` | `Twitter::Tweet` |
| --- | --- | --- |
| Time column | `post_created_at` | `tweet_created_at` |
| Own identifier | `uri` | `tweet_id` |
| Thread identifier | `thread_root_uri` | `conversation_id` |

`build_blocks` gets the name of the time column and a thread-key method as
parameters. Thus one method is sufficient for the two platforms.
`method(:bluesky_thread_key)` makes the `Method` object for this parameter.

## 8. How the code makes the threads

`bluesky_thread_key` and `twitter_thread_key` calculate the thread key:

- If the record has a thread identifier, the key is the thread identifier.
- If the record has no thread identifier, the key is the own identifier.

A single post thus makes a group with one member.

`build_blocks` then does these operations for each group:

1. It puts the records of the group in order of time.
2. It finds the record with a thread key equal to its own identifier.
   This record becomes the `root`.
3. If no record obeys the condition in step 2, the first record becomes the `root`.
4. It makes a `DraftBlock`. The other records become the `thread_members`.

At the end, `build_blocks` puts all blocks in order of the time of the `root`.

Step 3 is important. The database can contain a reply without the first post of
the thread. The reply then becomes the `root`.

`root_identifier` gives the own identifier of a record.
It gives `uri` for a Bluesky post and `tweet_id` for a tweet.

## 9. How the code puts a block into a section

`add_blocks` does these operations for each block:

1. It reads the `section` value of the `root` record, for example `'article'`.
2. `Newsletter::SectionTaxonomy.for` changes this value into a section definition.
3. It reads the `:key` value from the definition.
4. If the Hash has this key, it adds the block to that Array.
5. If the Hash does not have this key, it does not add the block.

Only the `root` record controls the section.
The code does not read the `section` value of the other thread members.

Step 5 is a safety condition. `SectionTaxonomy.for` gives the section
`'code_and_ruby'` for an unknown value. All sections are in the Hash.
Thus the code usually does not discard a block.

## 10. The exclusions

A user can remove a post from an edition.
The application then makes an `EditionExclusion` record.
This record has a polymorphic reference with the name `excludable`.

`excluded_records(model)` reads these records for one model name.
It gives the related posts or tweets.

The class uses the exclusions in two ways:

**Direct exclusion.** `excluded_bluesky_ids` and `excluded_twitter_ids` give the
primary keys of the excluded records. The query removes these records with
`where.not(id: ...)`.

**Thread exclusion.** `excluded_bluesky_thread_roots` and
`excluded_twitter_thread_roots` keep only the excluded records that are the
first post of a thread. The test is `thread_root_uri == uri` for Bluesky and
`conversation_id == tweet_id` for Twitter. The query then removes all records
with this thread identifier.

The result of these two rules:

- If the user excludes the first post of a thread, the code removes the full thread.
- If the user excludes a reply, the code removes only that reply.

`without_bluesky_root_exclusions` and `without_twitter_root_exclusions` give the
scope back with no change if the list is empty.
This prevents an unnecessary SQL condition.

The four exclusion methods keep their result in an instance variable with the
prefix `@_`. Thus each method reads the database one time.
`excluded_records` runs two times for each platform: one time for the
identifiers and one time for the thread roots.

## 11. Other data

- A post with `hidden` equal to `true` is never in the result.
- The result contains the empty sections. The caller must remove them.
  `Newsletter::EditionMarkdown` does this with `select`.
- Each call to `call` does the full work again. There is no cache between calls.
