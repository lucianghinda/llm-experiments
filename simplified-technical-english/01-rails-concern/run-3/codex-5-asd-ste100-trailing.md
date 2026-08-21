The [Idempotency concern](<app-root>/app/controllers/concerns/idempotency.rb:1) prevents a later duplicate API request from running the controller action again.

“Idempotency” means that a repeated request gives the same response without a second change to data.

### Request flow

1. The concern adds an `around_action` to the controller.

2. The code checks three conditions:

   - The request has an `Idempotency-Key` header.
   - The method is `POST`, `PATCH`, or `PUT`.
   - `Current.api_token` exists.

   If one condition is false, the controller action runs normally.

3. The code creates a cache key. The key contains:

   - The account ID
   - The controller and action
   - The request path
   - The idempotency key

4. The code calculates a SHA-256 hash of the request body. A hash is a short fingerprint of data.

5. The code looks for an earlier response in `Rails.cache`.

6. If an earlier response exists, the code compares the body hashes.

   - If the hashes are different, the code raises a conflict error.
   - If the hashes are equal, the code returns the cached response.
   - The controller action does not run again.

7. If no cached response exists, the controller action runs.

8. If the action raises an error, the concern calls the matching Rails `rescue_from` handler. This action lets the concern cache handled `4xx` responses.

9. The code caches responses with status codes from `200` through `499`. It does not cache `5xx` server errors.

### Cached data

The cache entry contains:

- The response status
- The response body
- Selected response headers
- The request body hash
- The creation time

The entry expires after 24 hours.

A replayed response also has this header:

```text
Idempotent-Replayed: true
```

### Failure behavior

A cache read or write error does not stop the request. The code writes a warning to the Rails log.

The code does not cache streaming responses.

This implementation does not lock concurrent requests. Two identical requests that arrive at the same time can both find an empty cache. Both controller actions can then run.