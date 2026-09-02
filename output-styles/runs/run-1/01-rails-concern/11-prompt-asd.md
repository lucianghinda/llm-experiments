## `app/controllers/concerns/idempotency.rb`

**Terms:** *idempotency key* = the value of the `Idempotency-Key` header. *Entry* = the record in the cache. *Replay* = to send an old response again.

### Function

This concern makes a repeated write request safe. If the client sends the same request two times, the server does the work one time only. The second time, the server sends the stored response again.

### Constants

- `WRITABLE_METHODS` — the concern is active for POST, PATCH, and PUT only.
- `TTL` — the cache keeps each entry for 24 hours.
- `HEADER` — the name of the header is `Idempotency-Key`.
- `CACHED_HEADERS` — the cache keeps six headers only: `Content-Type`, `Location`, and the four `X-RateLimit-*` headers.

### Sequence

The concern adds an `around_action`. This filter runs before and after each controller action.

1. **The filter reads the header.** If the header is empty, or if the method is not a write method, or if there is no `Current.api_token`, the filter does nothing. It runs the action in the usual manner (line 23).
2. **The filter makes a cache key.** The key contains the account ID, the controller path, the action name, the request path, and the idempotency key (line 56). Thus one account cannot read the entry of a different account. Also, the same key on a different endpoint is a different entry.
3. **The filter makes a hash of the request body.** It uses SHA256 (line 26).
4. **The filter reads the cache.**

**If an entry is in the cache:**

- If the body hash is different from the stored body hash, the filter raises `Api::Error::Conflict`. This tells the client that it used one key for two different requests (lines 30–35).
- If the body hash is the same, the filter replays the response. It sets the stored headers, it adds the header `Idempotent-Replayed: true`, and it sets the stored body and the stored status (lines 89–94). The controller action does not run.

**If no entry is in the cache:**

- The filter runs the action (line 47).
- If the action raises an error, the filter calls `rescue_with_handler` (line 49). This is necessary because `rescue_from` runs outside of the `around_action`. Without this step, the code after `yield` does not run. The filter raises the error again if no handler is available.
- Then the filter writes the entry, but only if the status is 200 to 499 (line 52). Thus the cache keeps success responses and client-error responses. The cache does not keep server errors (5xx), because the client must be able to try again.

### Protection of the cache operations

- A read failure or a write failure does not stop the request. The concern records a warning in the log and continues (lines 61–63 and 85–87).
- The concern does not write an entry for a streaming response, because the body is an `Enumerator` or the response is chunked (lines 69–72).

### One limit

The concern writes the entry after the action is complete. It does not put a marker in the cache before the action. Thus, if two identical requests come at the same time, the two actions can run together.
