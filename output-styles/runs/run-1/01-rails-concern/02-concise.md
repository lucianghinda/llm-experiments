`Idempotency` is a controller concern implementing Stripe-style idempotent writes via an `around_action`.

**Gate (line 23).** It only engages when all three hold: an `Idempotency-Key` request header is present, the method is POST/PATCH/PUT, and `Current.api_token` is set (so it's API-token traffic, not session traffic). Otherwise it just `yield`s and behaves like a no-op.

**Cache key (line 56).** `idem:<account_id>:<controller#action>:<path>:<key>` — scoped per account, per endpoint, per path, so the same client key can't collide across tenants or actions.

**Replay path (lines 29–39).** If an entry exists for the key:
- It SHA256-hashes the raw request body and compares against the stored `body_hash`. A mismatch means the client reused a key with different content → raises `Api::Error::Conflict` (409) rather than returning the wrong cached result.
- On a match, `replay_cached_response` restores the stored status, body, and the whitelisted headers (`CACHED_HEADERS`: content type, `Location`, rate-limit headers), plus adds `Idempotent-Replayed: true` so the client can tell it wasn't re-executed. The action never runs.

**First-execution path (lines 46–52).** This is the subtle part, and the comment explains why: `rescue_from` handlers registered on the controller run *outside* an `around_action`, so if the action raises, the code after `yield` would never run and nothing would be cached. To still cache error responses, the concern calls `rescue_with_handler(error)` itself — that dispatches the controller's own `rescue_from` handler (which renders the 4xx JSON). If no handler matches, it re-raises so normal error handling takes over.

**Write policy (line 52).** Caches only when the final rendered status is 200–499. So 2xx successes *and* 4xx client errors are stored and replayed; 5xx and unhandled exceptions are not, letting the client safely retry after a server failure.

**Write guards (`write_idempotency_entry`).** Skips streaming/chunked responses (the body isn't a materialized string). Stores status, body, whitelisted headers, body hash, and `created_at`, with a 24-hour TTL.

**Failure mode.** Both cache read and write swallow exceptions and just log a warning — a cache outage degrades to non-idempotent behavior instead of breaking requests.

One gap worth knowing: there's no lock or reservation between the read and the write, so two concurrent requests carrying the same key can both miss the cache and both execute the action. It dedupes sequential retries, not simultaneous ones.
