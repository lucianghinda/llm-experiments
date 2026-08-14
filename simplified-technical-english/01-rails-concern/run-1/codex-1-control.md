This concern implements idempotent response replay for authenticated API write requests. It is included by `Api::BaseController` and installed as an `around_action`.

The flow in [idempotency.rb](app/controllers/concerns/idempotency.rb:1) is:

1. It activates only when all three conditions are true:

   - An `Idempotency-Key` header is present.
   - The method is `POST`, `PUT`, or `PATCH`.
   - `Current.api_token` is set.

   Otherwise, it simply runs the controller action normally. `GET` and `DELETE` requests are not covered.

2. It builds a cache key containing:

   ```text
   account + controller/action + request path + idempotency key
   ```

   This prevents collisions between accounts and endpoints. Tokens belonging to the same account share the namespace.

3. It hashes the raw request body with SHA-256.

4. If a cached entry exists:

   - A different body hash raises `Api::Error::Conflict`, preventing reuse of the key for different input.
   - A matching body skips the action completely and replays the cached status, body, and selected headers.
   - The replay includes `Idempotent-Replayed: true`.

5. If there is no cached entry, it runs the action and caches responses with status `200` through `499` for 24 hours.

The exception handling around `yield` is important. Normally, controller-level `rescue_from` handlers run outside this `around_action`, which would prevent the code after `yield` from caching handled errors. The concern therefore calls `rescue_with_handler` itself:

- Handled exceptions—typically rendered as 4xx responses—are cached.
- Unhandled exceptions are re-raised.
- 5xx responses are not cached.

Each cache entry stores the response status, body, body hash, creation time, and only these headers: content type, location, and rate-limit headers. Streaming or chunked responses are deliberately skipped.

Cache failures are fail-open: read or write errors are logged, but they do not fail the API request.

One notable limitation is concurrency: the read–execute–write sequence has no lock or atomic reservation. Two simultaneous first requests using the same key could both execute before either writes the cached result. Also, request matching hashes only the body—not query parameters—while `request.path` excludes the query string.