The concern adds idempotent request handling to API controllers through an `around_action`. It lets clients safely retry certain write requests without performing the action twice.

The flow in [idempotency.rb](app/controllers/concerns/idempotency.rb:1) is:

1. **Decide whether idempotency applies.**  
   It only activates when all three are true:

   - The request includes `Idempotency-Key`.
   - The method is `POST`, `PATCH`, or `PUT`.
   - `Current.api_token` is present.

   Otherwise, it simply runs the controller action normally with `yield`.

2. **Construct an isolated cache key.**  
   The key combines:

   ```text
   account + controller + action + request path + Idempotency-Key
   ```

   Including the account prevents one account from replaying another account’s response.

3. **Fingerprint the request body.**  
   It computes a SHA-256 hash of the raw request body:

   ```ruby
   Digest::SHA256.hexdigest(request.raw_post.to_s)
   ```

4. **Check for a previous response.**

   - If there is no cached entry, the controller action runs.
   - If an entry exists and its request-body hash matches, the action is skipped and the cached response is replayed.
   - If the same idempotency key was previously used with a different body, it raises an API `409 Conflict`.

5. **Handle controller errors before caching.**  
   Because Rails normally applies `rescue_from` outside an `around_action`, the concern invokes `rescue_with_handler` itself. This allows handled errors—typically rendered 4xx API responses—to be cached too. Exceptions without a registered handler are re-raised.

6. **Cache eligible responses for 24 hours.**  
   Responses with statuses from `200` through `499` are cached. Each entry stores:

   - Status
   - Response body
   - Selected response headers
   - Request-body hash
   - Creation time

   Server errors (`5xx`) are not cached.

7. **Replay cached responses.**  
   On retry, it restores the status, body, and selected headers, then adds:

   ```http
   Idempotent-Replayed: true
   ```

A couple of important boundaries:

- Cache failures are deliberately non-fatal: reads behave as cache misses and writes are skipped after logging a warning.
- Streaming/chunked responses are not cached.
- There is no in-flight lock. Two identical requests arriving simultaneously before either finishes could both execute.
- Only the raw body is compared; query parameters and most headers are not part of the request fingerprint.
- `DELETE` requests are not covered.