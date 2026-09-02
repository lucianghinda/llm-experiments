## What it is

`Idempotency` is a controller concern that makes API write requests safe to retry. If a client sends the same request twice with the same `Idempotency-Key` header, the second call does not run the action again — it returns the stored response from the first call.

## When it activates

`around_action :wrap_in_idempotency` wraps every action in controllers that include it, but the logic only engages when all three are true (`idempotency.rb:23`):

1. The `Idempotency-Key` header is present.
2. The HTTP method is `POST`, `PATCH`, or `PUT` (reads are already idempotent).
3. `Current.api_token` is set — so it applies to API traffic only, not browser sessions.

Otherwise it just `yield`s and the action runs normally.

## The cache key

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The key is scoped by account, controller#action, and path — not just the client's key. So two different accounts (or two different endpoints) can use the same `Idempotency-Key` string without colliding. Entries live in `Rails.cache` for 24 hours (`TTL`).

## The two paths

**Cache hit (`:29`)** — the request was seen before:

- It first compares `body_hash`, a SHA256 of the raw request body, against the stored one. If the bodies differ, it raises `Api::Error::Conflict`. This is the standard rule: reusing a key with different content is a client bug, not a retry.
- If the bodies match, `replay_cached_response` copies the stored status, body, and a whitelist of headers (`CACHED_HEADERS` — content type, `Location`, rate-limit headers) onto the current response, adds `Idempotent-Replayed: true`, and returns. The action body never executes.

**Cache miss (`:46`)** — first time:

- It runs the action inside a `begin/rescue`. This is the subtle part, and the comment at `:41` explains why: `rescue_from` handlers are installed at the controller level, which is *outside* this `around_action`. If the action raised, the exception would blow past line 52 and the cache write would be skipped — even though the controller would go on to render a clean 422. So the concern calls `rescue_with_handler(error)` itself to render the error response in place, and re-raises only if no handler matched.
- Then it caches the result when the status is 2xx, 3xx, or 4xx (`>= 200 && < 500`). 5xx is deliberately *not* cached — a server error should be retryable rather than permanently replayed.

## Defensive details

- Both cache read and write rescue `StandardError` and only log a warning. A cache outage degrades to "the action just runs normally" instead of failing the request.
- `write_idempotency_entry` skips streaming responses (`Enumerator` body or `Transfer-Encoding: chunked`) — you cannot buffer those into a cache entry without consuming the stream.
- Only whitelisted headers are stored, so per-request things like cookies or request IDs are not replayed.

## One gap worth knowing

There is no lock or "in-flight" marker. The cache entry is only written *after* the action completes, so two identical requests arriving concurrently will both miss the cache and both execute the action. This protects against sequential retries (the common case: client timeout, then retry), not against simultaneous duplicates.
