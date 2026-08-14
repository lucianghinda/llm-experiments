The [Idempotency concern](app/controllers/concerns/idempotency.rb:1) makes API write requests safer to retry.

For example, if a client sends a request to create something but loses the response, it can repeat the request with the same `Idempotency-Key`. The server returns the original response instead of performing the action twice.

How it works:

1. It wraps every action in `Api::BaseController` with an `around_action`.

2. Idempotency is enabled only when:

   - The request has an `Idempotency-Key` header.
   - The method is `POST`, `PUT`, or `PATCH`.
   - The request has an authenticated API token.

   Otherwise, the controller action runs normally.

3. It creates a cache key containing:

   - The API token’s account ID.
   - The controller and action.
   - The request path.
   - The supplied idempotency key.

   This prevents one account or endpoint from reusing another account’s cached response.

4. It calculates a SHA-256 hash of the raw request body. This lets it detect whether a repeated key is being used for a different request.

5. On the first request:

   - The controller action runs.
   - Responses with status `200` through `499` are cached.
   - The cached data includes the status, body, selected headers, and body hash.
   - The cache entry expires after 24 hours.
   - `500` errors and streaming responses are not cached.

6. On a repeated request:

   - If the body matches, the controller action does not run again.
   - The saved response is returned.
   - The response gets `Idempotent-Replayed: true`.

7. If the same key is reused with a different request body, the server returns a conflict error rather than guessing which request is correct.

The concern also handles expected controller errors, such as rendered `4xx` responses, so those can be replayed too. Cache failures only produce warning logs; they do not stop the request.

One important limitation: there is no lock around the first execution. Two identical requests arriving simultaneously before either response is cached could both execute.