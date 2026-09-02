## What it does

`Idempotency` is a controller concern that makes write requests **safe to retry**. If a client sends the same request twice with the same `Idempotency-Key` header, the second request does not run the action again — it returns the stored response from the first one.

## The main flow (`wrap_in_idempotency`, `app/controllers/concerns/idempotency.rb:21`)

It runs as an `around_action`, so it wraps every controller action.

**1. Decide whether to apply at all (line 23)**

Three conditions must all be true:
- the request has an `Idempotency-Key` header,
- the HTTP method is `POST`, `PATCH`, or `PUT` (reads are naturally idempotent),
- there is an authenticated API token (`Current.api_token`).

If any is missing, it just `yield`s — the action runs normally, no caching.

**2. Build the cache key and a body fingerprint (lines 25–26)**

The cache key (line 56) is scoped to account + controller + action + path + the client's key:

```
idem:<account_id>:<controller>#<action>:<path>:<key>
```

Scoping by `account_id` means one tenant's key can never collide with another's. It also hashes the raw request body with SHA‑256 to fingerprint *what* was sent.

**3. If there is a cached entry (lines 29–39)**

- **Different body hash → error.** The same key used with a different payload is a client bug, so it raises `Api::Error::Conflict`. This is the standard Stripe behavior.
- **Same body → replay.** `replay_cached_response` (line 89) copies the stored headers and status onto the current response, sets the body, and adds `Idempotent-Replayed: true` so the client can tell it got a replay. It `return`s without calling `yield`, so **the action never executes**.

**4. If there is no cached entry (lines 46–52)**

It runs the action, then stores the result. The `begin/rescue` block is the subtle part, and the comment explains why:

Rails' `rescue_from` handlers run at the controller level, which is *outside* this `around_action`. So if the action raises, the exception would blow past line 52 and the cache write would be skipped. To still cache error responses, the concern calls `rescue_with_handler(error)` itself. That method returns truthy if a handler existed and rendered a response; if it returns falsy (`nil`), the exception is re-raised and bubbles up normally.

**5. What gets cached (line 52)**

Only statuses `200–499`. So successes *and* client errors (400, 404, 422) are replayed, but 5xx server errors are not — a server failure should be genuinely retryable.

## Storage details (`write_idempotency_entry`, line 66)

- **Streaming responses are skipped** (line 69): if the body is an `Enumerator` or the response is chunked, reading `response.body` would consume the stream, so it logs and bails.
- It stores status, body, a whitelist of headers (`CACHED_HEADERS` — content type, `Location`, and the rate-limit headers), the body hash, and a timestamp.
- TTL is 24 hours.

## Failure handling

Both `read_idempotency_entry` and `write_idempotency_entry` wrap everything in `rescue StandardError`, log a warning, and continue. This is deliberate: **the cache is not allowed to break the API**. If Redis/SolidCache is down, a read failure returns `nil` (the action just runs normally) and a write failure is silent.

## One behavior worth knowing

There is no "in-flight" marker. The entry is only written *after* the action finishes, so two truly concurrent requests with the same key can both miss the cache and both execute the action. This design protects against **sequential retries** (client times out, retries a second later), not against simultaneous duplicates. If you need that, the usual fix is writing a "processing" placeholder before `yield` and returning `409` on a hit.
