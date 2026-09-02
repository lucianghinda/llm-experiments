Here's how `app/controllers/concerns/idempotency.rb` works.

## The problem it solves

An API client sends `POST /api/v1/posts`, the connection drops before the response arrives, and the client retries. Without protection, you've now created two posts. The fix is the [Stripe-style idempotency key](https://docs.stripe.com/api/idempotent_requests): the client generates a unique key, sends it in a header, and the server promises that a repeat of that key returns the *original* response rather than re-executing the action.

## The gate (line 21-23)

```ruby
key = request.headers[HEADER]
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Three conditions must all hold, otherwise the action just runs normally:

- **A key was sent** — this is opt-in. No header, no bookkeeping.
- **The method is POST/PATCH/PUT** — `GET` and `HEAD` are already idempotent by HTTP semantics, and `DELETE` is too (deleting twice leaves the same state), so none need this.
- **`Current.api_token` exists** — this is API-only. Browser sessions don't get it, which matters because the token supplies the tenant scope for the cache key.

## The cache key (line 55-57)

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

Note how much is baked in beyond the client's key. `account_id` is the multi-tenancy boundary — Account A's key can never collide with Account B's, even if both clients pick the same UUID. The controller, action, and path mean the same key reused against a *different* endpoint is treated as a fresh request rather than replaying an unrelated response.

## The body fingerprint (lines 26, 30-35)

```ruby
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

On a hit, the concern compares the incoming body's hash against the stored one. If they differ, it raises `Api::Error::Conflict` (409) instead of replaying. This is the honest failure mode: the client reused a key for genuinely different data, which is a client bug. Silently replaying the old response would hide it; silently executing the new one would break the idempotency promise. Hashing rather than storing the body keeps the cache entry small and avoids parking raw request payloads (possibly containing secrets) in the cache.

## The `rescue_with_handler` trick (lines 41-50)

This is the subtlest part of the file, and the comment explains why:

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

`around_action` wraps the action, but `rescue_from` handlers live *outside* that wrapper in Rails' callback chain. So if the action raises `Api::Error::NotFound`, the exception propagates straight through the `around_action` — line 52 never runs — and only *then* does `rescue_from` convert it into a clean 404 JSON body. The cache write would be skipped entirely.

That's a problem because Stripe's contract says 4xx responses are cached and replayed too. So the concern calls `rescue_with_handler` itself, which looks up and invokes the matching `rescue_from` handler in-place. If a handler exists, it renders the error response and returns truthy — execution falls through to line 52 with `response.status` already set to 404. If no handler matches, it returns `nil` and the `raise` re-raises, preserving normal error behavior for genuine bugs.

`★ Insight ─────────────────────────────────────`
- `rescue_with_handler` is a documented public API on `ActiveSupport::Rescuable`, not a private hack — but reaching for it means you're deliberately running a handler earlier in the stack than Rails would. Worth the comment it got.
- The `raise unless` idiom is doing real work: bare `raise` inside a `rescue` re-raises the *current* exception with its original backtrace intact, so unhandled errors reach your error tracker looking untouched.
`─────────────────────────────────────────────────`

## What gets cached (line 52, 66-87)

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

**2xx–4xx are cached; 5xx are not.** That asymmetry is deliberate. A 4xx is a deterministic verdict about the request — retrying won't change it, so replaying is correct and saves work. A 5xx might be a transient database blip, so the client *should* be allowed to genuinely retry and succeed.

Two guards protect the write:

- **Streaming responses are skipped** (line 69). Reading `response.body` on an `Enumerator` would consume the stream, so the client would receive nothing. Skipping the cache degrades to "no idempotency" — annoying but safe. Consuming the stream would be data loss.
- **Both read and write swallow exceptions** (lines 61, 85), logging a warning. The cache is an availability-optional dependency: if Redis or SolidCache is down, requests should still succeed unprotected rather than 500. A failed read returns `nil`, which simply means "cache miss, run the action."

The stored entry keeps only whitelisted headers (`CACHED_HEADERS`) — content type, `Location`, and rate-limit counters. Replaying `Set-Cookie` or a stale `ETag` would be actively wrong, so the allowlist is safer than a blocklist here.

## The replay (lines 89-94)

```ruby
response.set_header("Idempotent-Replayed", "true")
```

The replay sets the cached headers, body, and status directly and — critically — never calls `yield`, so the action body never executes. The extra `Idempotent-Replayed` header is a courtesy: the client can distinguish "my write succeeded just now" from "my write succeeded earlier and this is a recording," which is useful for debugging and metrics.

## One thing worth knowing about

There's a race window between the read (line 27) and the write (line 52). Two concurrent requests with the same key can both miss the cache and both execute the action. The Stripe-style fix is to write a "in progress" sentinel before yielding and return 409 on hit, but that costs an extra cache round-trip on every request. Whether that matters depends on whether your clients retry aggressively in parallel — worth checking against how the API is actually used before treating it as a bug.

I couldn't verify which controllers include this concern (the search command needed approval I don't have), so if you want to trace the actual usage sites, let me know and I'll ask for that permission.
