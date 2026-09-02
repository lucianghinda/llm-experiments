Here's how `app/controllers/concerns/idempotency.rb` works.

## The shape

It's an `ActiveSupport::Concern` that installs a single `around_action :wrap_in_idempotency` (line 17) on any controller that includes it. Everything else is a private helper.

## The gate (line 23)

```ruby
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Idempotency only engages when all three hold: the client sent an `Idempotency-Key` header, the verb is POST/PATCH/PUT, and there's an authenticated API token. Anything else (GET, browser sessions, no header) just passes straight through — zero overhead, zero behavior change.

## The cache key and body fingerprint

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The key is namespaced by account, controller#action, and path, so the same client-supplied key reused against a different endpoint (or by a different tenant) can't collide. Separately, it fingerprints the request body with SHA-256 (line 26) and stores that alongside the response.

## Cache hit → replay or conflict (lines 29–39)

- **Body hash differs** → raise `Api::Error::Conflict` with a 409-style message. This is the Stripe contract: reusing a key with a *different* payload is a client bug, not a retry.
- **Body hash matches** → `replay_cached_response` copies the allowlisted headers (`CACHED_HEADERS`, lines 7–14 — content type, `Location`, rate-limit headers), adds `Idempotent-Replayed: true`, and assigns `self.response_body` and `response.status` directly. Then it `return`s **without ever calling `yield`**, so the controller action never runs. That's the whole point: the side effect happens once.

## Cache miss → run, then record (lines 41–52)

The `begin/rescue` block here is the subtle part, and the comment explains it: `rescue_from` handlers are registered at the controller level and run *outside* the `around_action`, so if the action raises, the stack unwinds past this method and the `write_idempotency_entry` line below would be skipped entirely. To still cache 4xx responses, the concern calls `rescue_with_handler(error)` itself — that dispatches the matching `rescue_from` handler (which renders the error response) and returns truthy; if no handler matches it returns nil and the `raise` re-throws for the normal Rails error path.

Then:

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

2xx/3xx/4xx are cached; **5xx deliberately are not**, so a server error is retryable with the same key.

## Writing (lines 66–87)

Skips streaming/chunked responses (can't serialize an `Enumerator` body), then writes `{status, body, headers, body_hash, created_at}` with a 24-hour TTL.

## Fail-open error handling

Both `read_idempotency_entry` and `write_idempotency_entry` rescue `StandardError`, log a warning, and continue. If the cache backend is down, requests still succeed — availability is chosen over the idempotency guarantee.

## Two behaviors worth knowing about

- **No in-flight lock.** The entry is only written *after* the action completes. Two concurrent requests carrying the same key both see a cache miss and both execute the action. This is a replay cache for sequential retries, not a concurrency guard. A reservation-on-entry pattern (write a "processing" sentinel before `yield`, return 409 on hit) would be needed for that.
- **Query string isn't part of the identity.** The cache key uses `request.path`, which excludes the query string, and the fingerprint covers only `request.raw_post`. Two POSTs with the same key and same body but different query params would replay the first response.
