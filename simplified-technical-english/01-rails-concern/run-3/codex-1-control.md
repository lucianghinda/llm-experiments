[Idempotency](<app-root>/app/controllers/concerns/idempotency.rb:1) prevents authenticated API write requests from being executed twice when clients retry them.

The request flow is:

1. It registers `wrap_in_idempotency` as an `around_action`.
2. It activates only when:

   - An `Idempotency-Key` header is present.
   - The method is `POST`, `PATCH`, or `PUT`.
   - `Current.api_token` is set.

3. It builds a cache key scoped to the account, controller action, request path, and supplied idempotency key:

   ```text
   idem:<account>:<controller>#<action>:<path>:<idempotency-key>
   ```

4. It hashes the raw request body with SHA-256.

5. On a cache miss, it executes the action and caches responses with statuses from `200` through `499` for 24 hours. The entry contains:

   - Response status
   - Response body
   - Selected content, location, and rate-limit headers
   - Request-body hash
   - Creation time

6. On a cache hit:

   - If the request-body hash matches, the action is skipped and the cached response is replayed with `Idempotent-Replayed: true`.
   - If the body differs, it raises a conflict error because the key was reused for a different operation.

The special exception handling around `yield` matters. Normally, an exception handled by Rails’ `rescue_from` would bypass the code following the action. The concern invokes `rescue_with_handler` itself so handled 4xx responses can still be cached. Unhandled exceptions are re-raised, and 5xx responses are not cached.

It is deliberately failure-tolerant: cache read or write errors are logged but do not fail the API request. Streaming and chunked responses are not cached.

Two notable limitations:

- This is not a concurrency lock. Two simultaneous requests can both observe a cache miss and execute.
- `request.path` excludes the query string, so query parameters are not part of the cache identity. The cache is also account-scoped rather than individual-token-scoped.