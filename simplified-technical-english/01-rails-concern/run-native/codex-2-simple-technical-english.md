The `Idempotency` concern prevents the same API write request from running more than once.

It adds an `around_action`. This code runs before and after each controller action.

The protection applies only when all these conditions are true:

- The request has an `Idempotency-Key` header.
- The HTTP method is `POST`, `PATCH`, or `PUT`.
- The request uses an API token.

If any condition is false, the controller action runs normally.

For a protected request, the concern builds a cache key. The key includes:

- The API account ID
- The controller and action
- The request path
- The idempotency key from the header

It also calculates a SHA-256 hash of the request body.

The concern then checks `Rails.cache`.

If it finds a cached response, it compares the saved body hash with the new body hash.

- If the hashes are different, it raises a conflict error. The client cannot reuse the same idempotency key with a different request body.
- If the hashes are the same, it returns the saved response. The controller action does not run again.

The replayed response contains the saved status, body, and selected headers. It also contains this header:

```text
Idempotent-Replayed: true
```

If there is no cached response, the controller action runs.

The concern handles controller errors before it writes the cache entry. It uses the normal Rails error handler when one exists. It raises the error again when no handler exists.

After the action finishes, it caches responses with status codes from `200` through `499`. It does not cache server errors with status codes of `500` or higher.

Each cache entry contains:

- The response status
- The response body
- Selected response headers
- The request body hash
- The creation time

The cache entry expires after 24 hours.

The concern does not cache streaming or chunked responses.

Cache failures do not fail the API request. The concern writes a warning to the Rails log and continues.
