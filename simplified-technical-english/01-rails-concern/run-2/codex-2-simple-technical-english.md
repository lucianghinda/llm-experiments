This concern makes certain API requests safe to retry without performing the same operation twice.

It runs around every controller action that includes it, but activates only when:

- The request has an `Idempotency-Key` header.
- The HTTP method is `POST`, `PUT`, or `PATCH`.
- The request has an authenticated API token in `Current.api_token`.

How it works:

1. It creates a cache key using the API account, controller, action, request path, and supplied idempotency key.
2. It calculates a SHA-256 fingerprint of the request body.
3. It checks `Rails.cache` for a previous response.

If a cached response exists:

- With the same request body, it returns the stored status, body, and selected headers. It also adds `Idempotent-Replayed: true`.
- With a different request body, it raises a `409 Conflict`. This prevents callers from reusing the same idempotency key for a different operation.

If no cached response exists:

- The controller action runs normally.
- Handled errors, such as API validation errors, are rendered normally.
- Responses with status codes from `200` through `499` are cached for 24 hours.
- Server errors (`500` and above) are not cached, so the client can retry later.
- Streaming responses are not cached.

Cache read or write failures only produce warnings. They do not stop the API request.

In short: the first request performs the operation and stores its response. Repeating the same request with the same key returns that stored response instead of performing the operation again.

Source: [idempotency.rb](app/controllers/concerns/idempotency.rb:1)