I have the file. Here's how it works — and a couple of things worth noticing at the end.

`★ Insight ─────────────────────────────────────`
- `around_action` is the only filter type that can wrap *both* sides of an action in one method — `yield` is the action. That's what lets this concern short-circuit (never yield) on a replay.
- Rails' `rescue_from` handlers run at the *controller* level, outside `around_action` filters. So an exception raised inside `yield` blows past the code after it. This file works around that by calling `rescue_with_handler` manually — that's the trick at line 46-50.
`─────────────────────────────────────────────────`

## The contract it implements

This is the Stripe-style idempotency pattern: a client sends `Idempotency-Key: <uuid>` with a write request. If the request is retried (network timeout, mobile app retry), the server replays the *original* response instead of performing the side effect twice.

## Walking through `wrap_in_idempotency`

**1. The guard (line 23)** — three conditions must hold, or it just yields and gets out of the way:
- a key header is present
- the method is POST/PATCH/PUT (`GET`/`DELETE` are already idempotent by definition)
- `Current.api_token` exists — so this only applies to authenticated API traffic, not browser sessions

**2. The cache key (line 56)**
```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```
Scoping by `account_id` is the important part: two tenants that happen to generate the same UUID can't collide, and one account can't probe another's cached responses. Including controller/action/path means the same key reused against a *different* endpoint gets its own entry rather than replaying an unrelated response.

**3. Replay path (lines 29-39)** — if there's a cached entry, it first compares a SHA-256 of the raw request body against the stored hash. Same key + different body means the client is misusing the key, and that's a `409 Conflict`, not a replay. Otherwise `replay_cached_response` writes the stored status, whitelisted headers, and body straight onto the response, plus `Idempotent-Replayed: true` so clients can tell. Note it `return`s **without yielding** — the action never runs, so no side effects.

**4. The exception dance (lines 41-50)** — the comment explains it well. Because `rescue_from` fires outside this filter, an exception in the action would skip line 52 entirely and nothing would be cached. So it rescues `StandardError` itself and asks `rescue_with_handler(error)` — a Rails internal that looks up the registered `rescue_from` handler and invokes it, returning truthy if one matched. If a handler ran, the response is now rendered (e.g. a 422 JSON error) and execution continues to the cache write. If nothing handled it, `raise` re-raises the bare exception and the normal 500 path takes over.

**5. What gets cached (line 52)** — status `200..499`. That's deliberate:
- 2xx: the successful result, obviously
- 4xx: client errors are *deterministic* — retrying with the same body will fail the same way, so replaying is correct and saves work
- 5xx: **not** cached, because those are usually transient. Retrying should genuinely re-attempt.

**6. `write_idempotency_entry` (lines 66-87)** — bails on streaming/chunked responses (you can't materialize an `Enumerator` body into the cache without consuming it), stores status/body/whitelisted headers/body hash/timestamp with a 24-hour TTL.

**7. Failure tolerance** — both the read and the write rescue `StandardError` and only log a warning. This is a deliberate design stance: **the cache is an optimization, not a correctness guarantee at the transport layer.** If Redis/SolidCache is down, requests still succeed — they just lose replay protection rather than 500ing.

`★ Insight ─────────────────────────────────────`
- `CACHED_HEADERS` is an allowlist rather than "cache everything". Replaying `Set-Cookie` or a stale `X-Request-Id` would be actively wrong, so only content-type, `Location` (for 201-created resources), and rate-limit counters survive.
- Hashing the body instead of storing it keeps entries small and avoids parking user PII in the cache for 24 hours while still detecting key misuse.
`─────────────────────────────────────────────────`

## Two things worth your attention

**No in-flight lock.** The check-then-write is not atomic. If a client fires two identical requests concurrently (a real retry pattern — the first hasn't responded yet, so nothing is cached), both pass the `cached.nil?` check and both execute the action. The usual fix is to write a sentinel `{status: :in_progress}` entry *before* yielding and return `409` on hitting it. Whether that matters depends on how your clients retry.

**Header casing under Rack 3.** Rails 8 runs Rack 3, where response header names are lowercase. `response.headers.slice("Content-Type", ...)` with capitalized keys may silently return an empty hash, meaning replayed responses lose their `Content-Type`. Worth a quick check in a console or an integration test asserting the replayed response's content type — if it's broken it fails quietly, which is the worst kind of broken.

Want me to write a test that exercises the replay path and confirms the header behavior?
