No MCP tool fits this; the `rails_*` tools are not connected and the CLI fallback was not approved, so I read the file directly (the user asked for this file specifically).

Here is the explanation of `build_blocks` (`app/services/edition/draft_query.rb:57`) in ASD-STE100 Simplified Technical English.

## Function

The method `build_blocks` makes a list of `DraftBlock` items from a list of social media records. Each `DraftBlock` has one root record and the other records of the same thread.

## Input data

The method receives three parameters:

1. `records` — a list of posts or tweets in time sequence.
2. `timestamp_method` — the name of the time attribute, for example `:post_created_at`.
3. `thread_key` — a method object. It gives the thread identifier of a record.

The method `bluesky_blocks` and the method `twitter_blocks` call `build_blocks`. Each one gives its own time attribute and its own thread key method.

## Steps

1. The method puts the records in groups. Records with the same thread key go in the same group. Each group is one thread.
2. For each group, the method puts the records in sequence by time. The oldest record is first.
3. The method identifies the root record of the thread. The root record is the record whose thread key is equal to its own identifier. The identifier is the URI for a Bluesky post, or the tweet ID for a tweet.
4. If the method does not find such a record, the method uses the first record of the group. This condition occurs when the true root is not in the date range, or a person made the root hidden.
5. The method makes a `DraftBlock`. The root record goes in the `root` field. All the other records of the group go in the `thread_members` field, in time sequence.
6. When all the groups are complete, the method puts all the blocks in sequence. It uses the time attribute of the root record of each block.

## Result

The method gives a list of `DraftBlock` items. The list is in sequence from the oldest thread to the newest thread. Subsequently, the method `add_blocks` puts each block in its newsletter section.
