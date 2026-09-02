Here's how `build_blocks` works — it's at `app/services/edition/draft_query.rb:57`.

## The signature

```ruby
def build_blocks(records, timestamp_method, thread_key)
```

It's called twice, once per platform (`draft_query.rb:40` and `:54`):

```ruby
build_blocks(records, :post_created_at,  method(:bluesky_thread_key))
build_blocks(records, :tweet_created_at, method(:twitter_thread_key))
```

The three arguments are the *only* things that differ between Bluesky and Twitter:

| Param | Bluesky | Twitter |
|---|---|---|
| `records` | `Bluesky::Post` array (already `.to_a`, ordered by SQL) | `Twitter::Tweet` array |
| `timestamp_method` | `:post_created_at` | `:tweet_created_at` |
| `thread_key` | `Method` → `thread_root_uri.presence \|\| uri` | `Method` → `conversation_id.presence \|\| tweet_id` |

Its job: **turn a flat list of posts into a chronologically ordered list of threads**, where each thread is a `DraftBlock` — a root post plus its replies.

## Step by step

**1. Group the flat list into threads**

```ruby
records.group_by { |record| thread_key.call(record) }.values
```

`bluesky_thread_key` (`:87`) returns `thread_root_uri.presence || post.uri`. So a reply keys on the URI of the thread it belongs to, and a standalone/root post — which has no `thread_root_uri`, or has one pointing at itself — falls back to its own URI. Every post in one conversation therefore produces the same key and lands in one bucket. `.values` throws the keys away; we just want the groups.

**2. Order each thread chronologically**

```ruby
ordered_records = thread_records.sort_by(&timestamp_method)
```

`&:post_created_at` — `Symbol#to_proc` turns the symbol into the accessor. This is belt-and-braces: the SQL already applied `.order(:post_created_at)` (`:37`) and `group_by` preserves input order, so the group is already sorted. It makes the method safe to call with an unsorted array.

**3. Find the thread's root — the interesting part**

```ruby
root = ordered_records.find do |record|
  thread_key.call(record) == root_identifier(record)
end || ordered_records.first
```

`root_identifier` (`:69`) returns the record's *own* identity: `uri` for a Bluesky post, `tweet_id` for a tweet. So the test is "does this record's thread key point at itself?"

- A root post: `thread_root_uri` is blank → key falls back to `uri` → `uri == uri` → **match**.
- A root post that self-references: `thread_root_uri == uri` → **match**.
- A reply: key is the *parent's* URI, which isn't its own URI → no match.

The `|| ordered_records.first` fallback handles **orphaned threads**. The root post may legitimately be missing from `records` — it could fall outside the edition's date window (`:26`), be `hidden: true`, or be explicitly excluded (`:32`). In that case the earliest surviving reply gets promoted to root so the thread still renders.

**4. Build the value object**

```ruby
DraftBlock.new(root: root, thread_members: ordered_records - [root])
```

`DraftBlock` is a `Data.define(:root, :thread_members)` (`:4`) — an immutable Ruby 3.2+ value object. `Array#-` uses `hash`/`eql?`, and ActiveRecord defines both in terms of class + primary key, so the root is removed by database identity rather than object identity — correct even if the same row were loaded into two separate instances.

**5. Sort the threads against each other**

```ruby
blocks.sort_by { |block| block.root.public_send(timestamp_method) }
```

Note this can't use the `&:sym` shorthand: the receiver is the `DraftBlock`, but the timestamp lives on `block.root`, so it has to hop one level with `public_send`.

## Why the root matters downstream

`add_blocks` (`:78`) files each block into a newsletter section using `block.root.section` — so **the root post's section decides where the entire thread is placed**. Getting root detection right isn't cosmetic; it determines which part of the newsletter a whole conversation appears in.

`★ Insight ─────────────────────────────────────`
- **Strategy-by-parameter instead of inheritance.** Rather than `BlueskyDraftQuery` / `TwitterDraftQuery` subclasses, the platform differences are passed in as a symbol and a `Method` object. `method(:bluesky_thread_key)` grabs a *private* method and hands back a callable — and calling it via `.call` legally bypasses the privacy, since privacy only restricts explicit-receiver dispatch, not `Method#call`.
- **The abstraction has one leak worth knowing about.** Two of the three platform variations are injected, but the third — `root_identifier` (`:69`) — is a hardcoded `case/when` on class. It returns `nil` for any unrecognised type, which would silently make the `find` fail and quietly fall through to `ordered_records.first`. Adding a Mastodon source means editing `build_blocks`' collaborator rather than just passing new arguments.
- **All of this is deliberately in Ruby, not SQL.** Both callers end in `.to_a` before calling `build_blocks`. Root-detection needs to know whether the root is *present in the filtered result set* — a fact that only exists after the window, `hidden`, and exclusion filters have all been applied, so it can't be expressed as a `GROUP BY`.
`─────────────────────────────────────────────────`

One process note: CLAUDE.md requires the `rails_*` MCP tools over `Read`. They aren't registered in this session, and the documented `bin/rails 'ai:tool[search_code]'` fallback wasn't approved, so I read the file directly and flagged it above. If you start `rails ai:serve` (or approve that bash command), I can use ground-truth tooling for follow-ups — particularly useful here to confirm the actual columns behind `thread_root_uri`, `conversation_id`, and `section`, which I've described from this file alone.
