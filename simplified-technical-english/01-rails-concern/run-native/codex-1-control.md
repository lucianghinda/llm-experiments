`Idempotency` is a controller concern that registers `wrap_in_idempotency` as an `around_action`. It is currently included by `Api::BaseController`.

It activates only when all three conditions are met:

- The request has a nonblank `Idempotency-Key` header.
- The method is `POST`, `PATCH`, or `PUT`.
- Authentication has populated `Current.api_token`.

Otherwise, it simply runs the controller action normally.

For an eligible request, it builds a cache key from the authenticated account, controller and action, request path, and supplied idempotency key. It also hashes the exact raw request body with SHA-256.

On a cache hit:

- If the stored body hash differs, it raises a `409 Conflict`. This prevents one idempotency key from being reused for a different payload. Because the raw body is hashed, semantically identical JSON with different whitespace or key ordering still counts as different.
- If the hash matches, it skips the action and restores the cached status, body, and selected headers. It adds `Idempotent-Replayed: true` so the caller can detect the replay.

On a cache miss, it runs the action. It explicitly invokes Rails’ configured `rescue_from` handlers for raised exceptions so handled errors—especially rendered 4xx API errors—can also be cached. Exceptions with no matching handler are re-raised.

Responses with status codes from 200 through 499 are cached for 24 hours. Each entry contains:

- Status
- Response body
- `Content-Type` and `Location`
- Rate-limit headers
- Request-body hash
- Creation timestamp

It does not cache 5xx responses, enumerator bodies, or chunked streaming responses.

Cache failures are deliberately non-fatal: read failures are treated as misses, and write failures merely produce warnings. Consequently, the mechanism is best-effort rather than a transactional guarantee. It also has no lock around the initial cache miss, so two simultaneous first requests using the same key could both execute before either writes its response.
