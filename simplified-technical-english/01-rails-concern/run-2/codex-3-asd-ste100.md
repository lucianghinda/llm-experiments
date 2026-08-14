The `Idempotency` concern prevents duplicate API write operations.

It is active in `Api::BaseController`.

How it works:

1. The concern runs before and after each controller action.
2. It checks the `Idempotency-Key` request header.
3. It operates only on `POST`, `PATCH`, and `PUT` requests.
4. It also requires a current API token.
5. If a condition is not true, the concern runs the action normally.

For a valid idempotency request:

1. The concern makes a cache key. The cache key contains:

   - The account ID.
   - The controller and action names.
   - The request path.
   - The idempotency key.

2. The concern calculates a SHA-256 hash of the request body.
3. The concern reads the cache.

If the cache contains an entry:

- If the body hash is different, the concern raises `Api::Error::Conflict`.
- If the body hash is the same, the concern returns the stored response.
- The controller action does not run again.
- The returned response has the `Idempotent-Replayed: true` header.

If the cache does not contain an entry:

- The concern runs the controller action.
- It also runs a controller error handler for an error that the application can handle.
- It stores responses with a status from 200 through 499.
- It does not store server-error responses with a status of 500 or more.

A cache entry contains:

- The response status.
- The response body.
- Selected response headers.
- The request-body hash.
- The creation time.

The selected headers are `Content-Type`, `Location`, and the four `X-RateLimit-*` headers.

The cache entry expires after 24 hours. The concern does not store streaming responses.

If a cache read or write fails, the concern writes a warning to the log. The request continues. Thus, a cache failure does not cause an API failure.