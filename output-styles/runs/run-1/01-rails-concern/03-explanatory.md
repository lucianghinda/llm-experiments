I read the file; the search tooling needed approval I didn't get, so this explanation is grounded in the file itself.

## What it is

`Idempotency` is a controller concern implementing the **Stripe-style `Idempotency-Key` contract**: a client sends a unique key with a write request, and if the request is retried (network timeout, mobile app retry, webhook redelivery), the server replays the original response instead of performing the side effect twice.

## The flow, step by step

**1. The guard (line 23)** — three conditions must all hold, otherwise it's a plain pass-through:

```ruby
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

`GET`/`DELETE` are excluded — `GET` is already safe, and `DELETE` is idempotent by HTTP semantics. Note this is scoped to API traffic only (`Current.api_token`), so browser/session requests never touch the cache.

**2. Cache key construction (line 56)**

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The `account_id` prefix is the important part — it's tenant isolation. Without it, account A could guess or collide with account B's key and receive B's cached response body. Including `controller#action` and `request.path` means the same client-generated key reused against a *different* endpoint is treated as a separate operation rather than a conflict.

**3. Request fingerprinting (line 26)** — the SHA-256 of the raw request body is stored alongside the response. On a cache hit with a *different* body hash, it raises `Api::Error::Conflict` (line 31). This is the correct behavior: a client reusing one key for two genuinely different payloads is a client bug, and silently replaying the first response would hide it.

**4. Replay (lines 89–94)** — on a matching hit it restores the whitelisted headers, sets `Idempotent-Replayed: true` so the client can tell a replay from a fresh execution, assigns `response_body` and `status`, and **returns without ever calling `yield`**. That's what makes it idempotent — the action body never runs.

The `CACHED_HEADERS` allowlist is deliberate: replaying `Content-Type`, `Location`, and the rate-limit headers is meaningful; replaying `Set-Cookie`, `ETag`, or `Date` from a day-old response would be actively wrong.

`★ Insight ─────────────────────────────────────`
- `around_action` is the only callback type that can *skip* the action entirely while still producing a response — a `before_action` would have to `render`, and an `after_action` runs too late. That's why replay-style caching is always built as an around filter.
- Storing a hash of the body rather than the body itself keeps the cache entry small and avoids retaining potentially sensitive request payloads in SolidCache for 24 hours.
`─────────────────────────────────────────────────`

## The clever part: the `rescue_with_handler` dance

Lines 41–50 are the non-obvious bit, and the comment explains why:

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

Rails' `rescue_from` handlers fire in `ActionController::Base#process_action`, which sits *outside* the callback chain. So if the action raises `Api::Error::NotFound`, the exception propagates up through this `around_action` — meaning line 52 (`write_idempotency_entry`) never executes, and the 404 would never be cached.

The fix is to invoke the rescue machinery manually. `rescue_with_handler` returns truthy if a registered handler matched (and has by then rendered the error response), falsy if none did. So:
- Handler found → swallow the exception, fall through to line 52, and the rendered 4xx status gets cached.
- No handler → `raise` re-raises, and the exception bubbles up normally to become a 500.

**5. Which responses get cached (line 52)** — `200..499`. Success *and* client errors are cached; 5xx is deliberately excluded. That's the right call: a 500 is usually transient (DB blip, timeout), and a retry with the same key should be allowed to actually re-execute rather than being permanently pinned to a failure.

## Failure posture

The concern **fails open** throughout. Both `read_idempotency_entry` and `write_idempotency_entry` rescue `StandardError`, log a warning, and continue. If the cache store is down, the API keeps serving requests — losing idempotency guarantees rather than losing availability. Line 69 similarly skips caching for streaming/chunked responses, where `response.body` would be an `Enumerator` that can't be meaningfully serialized (and consuming it would break the live response).

`★ Insight ─────────────────────────────────────`
- The `return unless Current.api_token` on line 67 is a redundant re-check — line 23 already guaranteed it. It's harmless defensive coding, but it hints the author was worried about `Current` being reset mid-request.
- `created_at` is written into the entry but never read anywhere in this file. It's presumably for debugging or a future `Idempotency-Key-Age` style header, since `expires_in: TTL` already handles expiry.
`─────────────────────────────────────────────────`

## Two sharp edges worth knowing about

**No in-flight locking.** The cache is only written *after* the action completes. If two identical requests arrive concurrently (the classic double-click / aggressive retry case), both read a cache miss, both execute the action, and both create the resource. Stripe's implementation takes a lock on the key at request start and returns a 409 for a request already in progress. If duplicate-under-concurrency is the actual threat model here, this concern doesn't cover it — it only covers sequential retries.

**Callback ordering matters.** Line 23 evaluates `Current.api_token` *before* yielding. Rails runs callbacks in registration order, and an `around_action` registered early wraps everything registered after it. So if `include Idempotency` appears above the API authentication `before_action` in the including controller, `Current.api_token` will still be `nil` at that point and idempotency silently becomes a no-op — no error, just quietly disabled. Worth confirming the include sits below the auth filter in whatever controller pulls this in.
