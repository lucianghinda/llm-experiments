The `Idempotency` concern prevents duplicate work when a client sends the same write request more than once.

A controller that includes this concern gets the `wrap_in_idempotency` action filter. This filter runs around each controller action.

The filter uses idempotency only when all these conditions are true:

- The request has an `Idempotency-Key` header.
- The request method is `POST`, `PATCH`, or `PUT`.
- `Current.api_token` exists.

If one condition is false, the controller action runs normally.

The filter makes a cache key from these values:

- The account ID
- The controller and action names
- The request path
- The idempotency key

The filter also calculates a SHA-256 hash of the request body.

The filter then reads the cache. If the cache read fails, the code logs a warning and runs the request normally.

If a cache entry exists, the filter compares the stored body hash with the new body hash. If the hashes are different, the code raises a conflict error. A client cannot use the same idempotency key for two different request bodies.

If the hashes are equal, the code does not run the controller action again. It restores the stored status, body, and selected headers. It also adds this response header:

```text
Idempotent-Replayed: true
```

If no cache entry exists, the filter runs the controller action. It also runs a controller error handler when the action raises an error. If no handler accepts the error, the code raises the error again.

The filter stores responses with status codes from 200 through 499. It does not store server-error responses with status codes of 500 or more.

Each cache entry contains:

- The response status
- The response body
- Selected response headers
- The request body hash
- The creation time

The cache entry expires after 24 hours.

The code does not store streaming responses. It also does not let a cache write error stop the response. It logs a warning when a cache write fails.
