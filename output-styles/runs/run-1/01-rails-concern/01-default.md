Here's the file: `app/controllers/concerns/idempotency.rb`. It's a Stripe-style idempotency layer implemented as an `around_action`.

## The gate (line 23)

```ruby
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Three conditions must all hold or the action just runs normally: the client sent an `Idempotency-Key` header, the verb is POST/PATCH/PUT (GET/DELETE aren't wrapped), and there's an authenticated API token. So this only affects the token-authenticated API surface, never browser/session traffic.

## Cache key and body fingerprint

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

Scoped per account *and* per endpoint, so one tenant's key can't collide with another's, and reusing the same key against a different endpoint is treated as a different operation.

Alongside it, `body_hash` is a SHA256 of `request.raw_post`. That's the "did you really send the same request" check.

## Hit path — replay

If an entry exists:

- **Body differs** → raises `Api::Error::Conflict` ("already been used with a different request body"), the standard 409 semantics for a reused key.
- **Body matches** → `replay_cached_response` writes the whitelisted headers back (`CACHED_HEADERS` — content type, `Location`, rate-limit headers), stamps `Idempotent-Replayed: true`, and sets `response_body` and `status` from the entry. It then `return`s **without yielding**, so the action body never executes — no duplicate charge, no duplicate record.

## Miss path — the `rescue_with_handler` trick (lines 41–50)

This is the non-obvious part, and the comment explains it. `rescue_from` handlers are invoked by `process_action` *outside* the `around_action` chain. So if the action raises, the exception propagates straight through `yield` and line 52 (the cache write) is never reached — the concern would never cache error responses.

To work around that, it catches `StandardError` and calls `rescue_with_handler(error)` itself. That dispatches the matching `rescue_from` handler inline (rendering, say, a 422), so control returns normally and the write can proceed. If no handler matches, `rescue_with_handler` returns nil and the error is re-raised for the normal Rails path.

## Writing the entry

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

2xx–4xx get cached for 24h; 5xx and unhandled exceptions deliberately do not, so a client can safely retry a server failure with the same key. Streaming/chunked responses are skipped (you can't snapshot an `Enumerator` body). Both the read and the write swallow cache exceptions and log a warning — a Redis/SolidCache hiccup degrades to "not idempotent" rather than failing the request.

## Two things worth knowing about the behavior

**No in-flight lock.** The entry is only written *after* the action finishes. Two concurrent requests with the same key both miss the cache and both execute the action. Stripe handles this by recording the key up front and returning 409 while a request is in flight; this implementation doesn't, so it protects against sequential retries but not simultaneous ones.

**4xx responses are sticky for 24h.** A validation failure gets cached, so a client that fixes the payload and retries with the same key gets a 409 (body changed) rather than a fresh attempt. That's consistent with the Stripe contract, but it means clients must mint a new key after a client error.

`created_at` is stored in the entry but not read anywhere in this file — expiry is handled entirely by the cache TTL.
