I have the file. I couldn't verify the collaborators (`Current.api_token`, `Api::Error::Conflict`) — those tool calls needed approval — so I'll flag where I'm inferring from the call sites rather than from their definitions.

## What it's for

This implements the **Stripe-style `Idempotency-Key` contract**: a client sends a unique key with a write request; if the request is retried (network timeout, mobile app retry, webhook redelivery), the server replays the original response instead of creating a second charge/record.

## The flow, step by step

### 1. The guard (line 23)

```ruby
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

`around_action` is registered unconditionally on every action of the including controller, so this line is what keeps it inert. Three conditions must hold: a key was sent, the verb actually mutates state (`GET`/`DELETE` are excluded — `DELETE` is already idempotent by definition), and there's an authenticated API token. That last one matters for more than authorization: `Current.api_token.account_id` is a component of the cache key, so without a token there'd be no tenant to scope to.

This also implies an ordering dependency — whatever `before_action` populates `Current.api_token` must run *before* this filter. In Rails, filters inherited from a parent controller run before ones declared in the child, so this works as long as authentication lives in the API base controller.

### 2. The cache key (line 56)

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

Note how much is packed in beyond the client's key. Account ID prevents one tenant replaying another tenant's response — critical, since keys are client-chosen and two tenants will collide on `"1"` sooner or later. Controller/action/path mean the same key reused against a *different* endpoint is treated as a fresh request rather than a conflict.

### 3. The body fingerprint (line 26)

```ruby
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

The key alone isn't enough. If a client reuses a key with a *different* payload, that's a client bug — replaying the old response would silently discard the new data. So the SHA-256 of the raw body is stored alongside the response, and a mismatch raises `Api::Error::Conflict` (line 31), which presumably renders 409 through the app's `rescue_from` chain. The hash is only compared, never used for lookup, so collisions aren't a security concern.

### 4. Replay (lines 89–94)

```ruby
self.response_body = entry[:body]
```

Assigning `response_body` is what makes the early `return` on line 38 legal — it marks the response as performed, so Rails doesn't raise a missing-template error for an action that never ran. Only an allowlist of headers is restored (`CACHED_HEADERS`), plus an `Idempotent-Replayed: true` marker so clients can tell a replay from a fresh execution.

`★ Insight ─────────────────────────────────────`
The header allowlist is deliberate. Blindly restoring all headers would replay stale `Set-Cookie`, `ETag`, and request-id values from a day-old response. The trade-off: the cached `X-RateLimit-Remaining` is frozen at its original value, so replays report stale quota. Stripe makes the same choice — treating the replay as a faithful reproduction of the original response, not a fresh one.
`─────────────────────────────────────────────────`

### 5. The clever/ugly part (lines 41–50)

This is the piece worth understanding:

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

The problem the comment describes is real. Rails' `rescue_from` handlers are installed by `ActiveSupport::Rescuable` at the level of `process_action`, which wraps the *entire* filter chain — so an exception raised inside the action unwinds straight through this `around_action` and only gets caught above it. Everything after `yield` would be skipped, meaning a 422 validation error would render fine but never get cached.

The workaround calls `rescue_with_handler` manually. That's the same `ActiveSupport::Rescuable` method the framework uses: it looks up a handler registered via `rescue_from`, invokes it (which renders the error response), and returns a truthy value. If no handler matches it returns nil and the bare `raise` re-raises the original exception, letting it become a real 500. As a bonus, `rescue_with_handler` recurses down `exception.cause`, so a wrapped exception with a registered handler for its cause is still handled.

### 6. What gets cached (line 52)

```ruby
if response.status >= 200 && response.status < 500
```

2xx and 4xx are cached; 5xx is not. That asymmetry is the point of the whole contract — a 500 might be transient (deadlock, timeout), so the client *should* be able to retry the same key and get a real second attempt. A 422 is deterministic: retrying will fail identically, so replaying it is both correct and cheaper.

### 7. Failure modes are non-fatal

Both cache read and write rescue `StandardError` and merely log (lines 61–63, 85–87). This **fails open**: if Redis/SolidCache is down, requests still succeed — you lose idempotency protection rather than availability. The streaming guard (line 69) is the same instinct: you can't buffer an `Enumerator` body into the cache, so it skips rather than blows up.

## Two gaps worth knowing about

**Concurrent duplicates aren't handled.** There's no "in-flight" marker written before `yield`. Two simultaneous requests with the same key both find an empty cache and both execute the action — exactly the double-charge the concern exists to prevent. This is the classic check-then-act race. Stripe's real implementation writes a lock record first and returns 409 for a request already in progress. If retries in this app come from a client with a short timeout (the case most likely to fire two requests near-simultaneously), this gap is reachable.

**`created_at` is stored but never read** (line 81). Expiry is handled entirely by `expires_in: TTL`, so it looks like it's there for debugging or a future "replayed from" header.
