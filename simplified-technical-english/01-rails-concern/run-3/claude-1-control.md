# How `Idempotency` works

`app/controllers/concerns/idempotency.rb` is an `ActiveSupport::Concern` mixed into `Api::BaseController`. It implements a Stripe-style `Idempotency-Key` contract: if a client retries the same write with the same key, the API returns the original response instead of doing the work twice.

## Configuration constants

- `WRITABLE_METHODS = %w[POST PATCH PUT]` — only mutating verbs are eligible. `GET`/`DELETE` requests are never intercepted.
- `TTL = 24.hours` — how long a cached response stays replayable.
- `HEADER = "Idempotency-Key"` — the request header the client sends.
- `CACHED_HEADERS` — the allowlist of response headers stored with the entry: `Content-Type`, `Location`, and the four `X-RateLimit-*` headers. It is an allowlist rather than a blocklist, so headers such as `Set-Cookie` can never be replayed to a different caller by accident.

## The hook

```ruby
included do
  around_action :wrap_in_idempotency
end
```

An `around_action` is required, not a pair of before/after callbacks, because the concern has to be able to *skip the action entirely* on a replay. Callbacks run in the order the concerns are included in `Api::BaseController`:

1. `ApiAuth#require_api_token` (before) — sets `Current.api_token`.
2. `Idempotency#wrap_in_idempotency` (around) — starts here.
3. `RateLimit#enforce_rate_limit` (before) — runs *inside* the `yield`.
4. The controller action.

That ordering matters twice over. Authentication has already run when the around-action begins, so `Current.api_token` is available for scoping the cache key. And rate limiting runs inside the yielded block, so a replay that returns early never touches the rate-limit counter — which is exactly why the `X-RateLimit-*` headers must be replayed from the cache entry.

## The main flow

```ruby
key = request.headers[HEADER]
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Three conditions must all hold, otherwise the concern gets out of the way and the request proceeds normally: a key was sent, the verb is a write, and the request is authenticated. The `Current.api_token` check is what makes the feature safe — without a token there is no account to scope the cache key to.

### Building the key and the body fingerprint

```ruby
cache_key = idempotency_cache_key(key)
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

The cache key is:

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

Four dimensions of scoping. `account_id` prevents one tenant from replaying — or colliding with — another tenant's response even if both send the same UUID. `controller_path#action_name` and `request.path` mean the same client key can be reused freely across different endpoints and different resources; it only dedupes a repeat of *the same* call. There are integration tests covering each of these (`test/integration/api/v1/url_quote_extractions_cross_account_test.rb`, `test/controllers/api/v1/articles_create_controller_test.rb`).

`body_hash` is a SHA-256 of the raw request body. It is stored alongside the response and used as a tamper check.

### Cache hit

```ruby
if cached
  if cached[:body_hash] != body_hash
    raise Api::Error::Conflict.new(...)
  end
  replay_cached_response(cached)
  return
end
```

Two outcomes:

- **Same key, different body** → `409 Conflict`. This catches a client bug where a key is reused for a genuinely different request. The error is raised from the around-action, before yielding; `rescue_from` in `ErrorResponder` wraps the whole callback chain, so it still renders as a proper JSON error payload.
- **Same key, same body** → `replay_cached_response` writes the allowlisted headers back, adds `Idempotent-Replayed: true` so the client can tell a replay from a fresh result, restores the body and the status, and returns. Because the around-action never yields, the rate limiter and the action itself are both skipped.

### Cache miss

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end

write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

This `begin/rescue` is the subtlest part of the file, and the comment above it explains why. `rescue_from` handlers are installed at the controller level, *outside* the around-action. If the action raises, the exception unwinds past this method before Rails renders the error — so any code after `yield` would simply never run, and 4xx responses would never get cached.

To honour the replay contract for client errors (a validation failure should replay as the same `422`, not silently re-run), the concern dispatches the rescue handler itself with `rescue_with_handler(error)`. That method renders the error response and returns the handler's result, or `nil` if no handler matched. If nothing matched, `raise` re-raises so the exception can propagate normally.

By the time control reaches the `write_idempotency_entry` line, `response.status` is set — whether the action rendered normally or an error handler rendered for it.

The status guard caches `2xx`, `3xx` and `4xx`, but not `5xx`. Server errors are treated as possibly transient, so a retry with the same key is allowed to actually re-run. Note that `429 Rate limited` falls inside the cached range, so a rate-limited request that carried an idempotency key will replay its `429` for the full 24 hours rather than being retryable.

## The helper methods

**`read_idempotency_entry`** wraps `Rails.cache.read` in a rescue that logs a warning and returns `nil`. This is a deliberate fail-open: if the cache is unavailable, the request is treated as new and runs. The trade-off is that a cache outage can allow a duplicate write.

**`write_idempotency_entry`** does three things before writing:

1. Re-checks `Current.api_token` (defensive; the caller already guaranteed it).
2. Refuses to cache streaming responses — an `Enumerator` body or `Transfer-Encoding: chunked`. Reading `response.body` on a streamed response would consume or block on the stream, so it logs and bails.
3. Writes a hash of `status`, `body`, allowlisted `headers`, `body_hash` and `created_at` with `expires_in: TTL`.

Like the read, the whole write is wrapped in a rescue that only logs. A cache failure must never turn a successful `201` into a `500`.

**`replay_cached_response`** rebuilds the response in place. Assigning `self.response_body` marks the response as performed, which is what allows the around-action to return without yielding.

## Behaviour summary

| Situation | Result |
|---|---|
| No key, or `GET`/`DELETE`, or unauthenticated | Passes straight through |
| First request with a key | Action runs, response cached for 24h |
| Retry, same key and body | Cached response replayed, `Idempotent-Replayed: true`, no rate-limit charge |
| Retry, same key, different body | `409 Conflict` |
| Action returns 4xx | Error response is cached and replayable |
| Action returns 5xx | Not cached; retry re-runs the action |
| Cache read or write fails | Logged, request proceeds as if uncached |
| Streaming response | Not cached |

## Known limits

- **No in-flight lock.** Two concurrent requests with the same key both miss the cache and both execute the action. The concern deduplicates sequential retries, not simultaneous ones.
- **Fail-open on cache errors.** Correctness depends on cache availability; an outage degrades to no idempotency rather than to an error.
- **`429` responses are cached**, as noted above, which makes a rate-limited call non-retryable under the same key for the TTL.
