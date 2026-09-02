`app/controllers/concerns/idempotency.rb` gives API write endpoints a Stripe-style idempotency contract: a client can retry a `POST`/`PATCH`/`PUT` with the same `Idempotency-Key` header and get the first response back, instead of a second side effect.

## The gate (line 23)

The concern installs one `around_action`. It does nothing and just yields unless all three conditions are true:

- the `Idempotency-Key` header is present,
- the method is `POST`, `PATCH`, or `PUT`,
- `Current.api_token` is set (so this covers API traffic only, not session traffic).

## The cache key (line 56)

```
idem:<account_id>:<controller#action>:<request path>:<client key>
```

The account id scopes the key per tenant. The controller, action, and path stop the same client key from replaying across different endpoints. Entries live for 24 hours (`TTL`).

## Hit path (lines 29-39)

On a cache hit, the concern compares a SHA-256 of the raw request body against the stored `body_hash`.

- **Different body** → raise `Api::Error::Conflict`. This is the "you reused a key for a different request" case.
- **Same body** → `replay_cached_response` writes the stored status, body, and the allow-listed headers (`CACHED_HEADERS`) onto the response, adds `Idempotent-Replayed: true`, and returns **without yielding**. The controller action never runs.

Note that the replayed `X-RateLimit-*` headers are the values from the *first* request, not current ones.

## Miss path (lines 46-52)

This is the subtle part, and the comment at line 41 explains why.

`rescue_from` handlers run at the controller level, which is *outside* this `around_action`. So if the action raises, the exception propagates past line 47 and the cache write at line 52 never happens. Validation errors (4xx) would then never be cached, and a retry would re-run the action.

The workaround: catch `StandardError` and call `rescue_with_handler(error)` manually. That dispatches the controller's own `rescue_from` handler, which renders the 4xx response in place. Then:

- Handler found → execution continues to line 52 with a rendered response.
- No handler → `raise` re-raises, so unhandled exceptions still bubble up as normal.

## What gets cached (line 52)

Status `200..499`. This is deliberate:

- **2xx and 4xx are cached.** A client error is a deterministic outcome, so replaying it is correct.
- **5xx is not cached.** A server error may be transient, so the client must be able to retry for real.

`write_idempotency_entry` also skips streaming responses (`Enumerator` body or `Transfer-Encoding: chunked`), because there is no body string to store.

## Failure mode

Both the cache read and the cache write rescue `StandardError`, log a warning, and continue. The concern **fails open**: if the cache backend is down, requests still work, they just lose idempotency protection.

## One gap worth knowing

There is no lock or "in-flight" marker. The entry is written only *after* the action completes. Two concurrent requests with the same key can both miss the cache and both execute the action. The concern protects against sequential retries, which is the common case, but not against a genuine race.
