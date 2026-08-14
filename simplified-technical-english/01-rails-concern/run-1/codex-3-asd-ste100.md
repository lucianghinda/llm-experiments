The [Idempotency concern](app/controllers/concerns/idempotency.rb) prevents one API operation from running more than one time.

`Api::BaseController` includes this concern. The concern adds an `around_action` callback.

How it works:

1. The callback reads the `Idempotency-Key` request header.
2. It continues without idempotency control if one condition is not true:

   - The header has a value.
   - The method is `POST`, `PATCH`, or `PUT`.
   - The request has a current API token.

3. It makes a cache key from these values:

   - Account ID
   - Controller and action
   - Request path
   - Idempotency key

4. It calculates a SHA-256 hash of the request body.
5. It searches the Rails cache for an earlier response.

If a cached response exists:

- The concern compares the two body hashes.
- It raises a conflict error if the request bodies are different.
- It replays the cached response if the request bodies are the same.
- The replay contains the original status, body, and selected headers.
- It also adds the header `Idempotent-Replayed: true`.
- The controller action does not run again.

If no cached response exists:

- The concern runs the controller action.
- It lets the controller handle known errors.
- This permits the concern to cache handled `4xx` responses.
- It caches responses with status codes from `200` through `499`.
- It does not cache `5xx` responses.
- The cache entry expires after 24 hours.

The concern does not cache streaming or chunked responses. A cache failure does not stop the request. The concern writes a warning to the Rails log instead.

In short, the first request does the work. An identical retry receives the stored response. A retry with different data receives a conflict error.