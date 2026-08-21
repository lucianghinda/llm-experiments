The [idempotency concern](<<app-root>/app/controllers/concerns/idempotency.rb:1>) prevents the repeated processing of some API requests.

### When it operates

The concern uses an `around_action`. It operates only when all these conditions are true:

- The request has an `Idempotency-Key` header.
- The HTTP method is `POST`, `PATCH`, or `PUT`.
- `Current.api_token` exists.

If one condition is false, the controller processes the request normally.

### First request

For a new idempotency key, the concern does these steps:

1. It makes a cache key. The cache key contains the account, controller, action, request path, and idempotency key.
2. It calculates a SHA-256 hash of the request body.
3. It searches the Rails cache for an earlier response.
4. If no response exists, it runs the controller action.
5. It stores the response when the status is from 200 through 499.

The cache entry contains:

- The response status
- The response body
- Selected response headers
- The request-body hash
- The creation time

The cache entry expires after 24 hours.

### Repeated request

If the cache contains an entry, the concern compares the request-body hashes.

If the hashes are equal, it does not run the controller action. It returns the cached status, body, and headers. It also adds this header:

```text
Idempotent-Replayed: true
```

Thus, a repeated request returns the first response.

If the hashes are different, it raises an `Api::Error::Conflict` error. This prevents one idempotency key from use with different request data.

### Error responses

The concern processes errors that have a Rails `rescue_from` handler. This permits it to cache rendered 4xx responses.

It raises the error again when no handler exists. It does not cache responses with a status of 500 or higher.

### Cache failures and streaming responses

A cache read or write failure does not stop the request. The concern writes a warning to the Rails log.

The concern does not cache streaming or chunked responses.

Important limitation: this code does not lock concurrent requests. Two requests that arrive at the same time can both run before the first response enters the cache.