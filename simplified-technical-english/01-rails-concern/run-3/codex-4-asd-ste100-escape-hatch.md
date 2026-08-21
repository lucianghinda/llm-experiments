The `Idempotency` concern prevents most duplicate API write operations. A client sends an `Idempotency-Key` header. The server saves the first response and can return that response for a matching retry.

The concern is included in [`Api::BaseController`](<app-root>/app/controllers/api/base_controller.rb:6), so it applies to its descendant controllers.

### Request flow

1. Rails runs `wrap_in_idempotency` around each controller action through `around_action` ([lines 16–18](<app-root>/app/controllers/concerns/idempotency.rb:16)).

2. The concern becomes active only when all these conditions are true ([line 23](<app-root>/app/controllers/concerns/idempotency.rb:23)):

   - The request has an `Idempotency-Key` header.
   - The method is `POST`, `PATCH`, or `PUT`.
   - `Current.api_token` exists.

   If one condition is false, the concern runs the action normally.

3. It creates a cache key from:

   - The authenticated account ID.
   - The controller and action.
   - The request path.
   - The supplied idempotency key.

   This prevents one account or endpoint from using another account’s cached response ([lines 55–57](<app-root>/app/controllers/concerns/idempotency.rb:55)).

4. It calculates a SHA-256 hash of the raw request body ([line 26](<app-root>/app/controllers/concerns/idempotency.rb:26)).

5. It looks for an existing cache entry.

### When a cached response exists

The concern compares the current body hash with the cached body hash.

- If the hashes differ, it raises `Api::Error::Conflict`. The client cannot reuse one key for a different request body.
- If the hashes match, it does not run the controller action. It restores the cached status, body, and selected headers. It also adds:

```http
Idempotent-Replayed: true
```

This behavior is in [lines 29–39](<app-root>/app/controllers/concerns/idempotency.rb:29) and [lines 89–94](<app-root>/app/controllers/concerns/idempotency.rb:89).

### When no cached response exists

The concern runs the action.

It also catches `StandardError` and asks the controller’s `rescue_from` handlers to process the error. This special step lets it cache handled `4xx` error responses. It raises the error again if no handler accepts it ([lines 41–50](<app-root>/app/controllers/concerns/idempotency.rb:41)).

It caches responses with status codes from `200` through `499`. It does not cache `5xx` responses ([line 52](<app-root>/app/controllers/concerns/idempotency.rb:52)).

Each entry contains:

- Status code.
- Response body.
- Selected response headers.
- Request-body hash.
- Creation time.

The cache expires after 24 hours. The concern does not cache streaming responses ([lines 66–84](<app-root>/app/controllers/concerns/idempotency.rb:66)).

### Failure behavior and limitation

Cache failures do not fail the API request. The concern logs cache read or write errors and continues. Therefore, idempotency is a best-effort feature.

It is also not a strict “exactly once” system. There is no cache lock or atomic reservation. Two concurrent requests with the same unused key can both run before either request writes its result.