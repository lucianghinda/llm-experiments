## Purpose

[`Edition::DraftQuery`](<app-root>/app/services/edition/draft_query.rb:3) builds the content structure for one newsletter edition.

It reads Bluesky posts and Twitter tweets. It does not change database data.

## Input and output

The initializer receives one `Edition` record.

The `call` method returns a hash:

- Each key identifies a top-level newsletter section.
- Each value is an array of `DraftBlock` objects.
- Each block contains one root record and its thread members.
- The hash also contains sections that have no blocks.

## Operation

1. The service creates an empty array for each top-level newsletter section.

2. It makes a time window from the start date to the end date.

   The window includes all times on both dates.

3. It gets visible Bluesky posts from the edition organization.

4. It gets visible Twitter tweets from the same organization.

5. It removes records that the edition explicitly excludes.

6. If the excluded record is a thread root, the service removes the complete thread.

7. It groups the remaining records into threads.

   Bluesky uses `thread_root_uri`. Twitter uses `conversation_id`.

8. It sorts each thread by its creation time.

9. It finds the root record.

   If the root is not available, the first record becomes the root.

10. It puts all other records in the `thread_members` array.

11. It assigns each block to the newsletter section of its root record.

12. It adds Bluesky blocks first. It adds Twitter blocks after them.

## Important behavior

- A hidden record cannot occur in the result.
- An excluded thread member does not remove the complete thread.
- An excluded thread root usually removes the complete thread.
- The service keeps the time order inside each platform.
- It does not make one common time order for both platforms.
- Bluesky blocks occur before Twitter blocks in each section.
- The `includes` calls load related data before the view uses it.
- The edition page, Markdown generator, and summarization job use this result.

This explanation uses the principal rules of [ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/assets/files/ASD-STE100_ISSUE9.pdf).