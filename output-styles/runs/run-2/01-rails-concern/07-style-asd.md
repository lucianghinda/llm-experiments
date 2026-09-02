## What the concern does

The `Idempotency` concern makes a repeated write request safe. If the client sends the same request two times, the server does the work one time only. The second request gets the first response again.

## When it becomes active

`around_action :wrap_in_idempotency` puts the code around every action of the controller (`app/controllers/concerns/idempotency.rb:17`).

The concern does its work only when these three conditions are true (`:23`):

- The request has an `Idempotency-Key` header.
- The method is `POST`, `PATCH`, or `PUT`.
- `Current.api_token` exists.

If one condition is false, the concern calls `yield` and does no more.

## The cache key

The key contains the account, the controller, the action, the path, and the client key (`:56`):

```
idem:<account_id>:<controller#action>:<path>:<client key>
```

Thus one client key cannot collide with a different account or a different endpoint.

## The flow

**1. Read the cache** (`:27`). The concern also calculates a SHA256 hash of the raw request body (`:26`).

**2. If an entry is in the cache:**

- If the body hash is different, the concern raises `Api::Error::Conflict` (`:30`). The client used the same key with different data.
- If the body hash agrees, the concern replays the stored response (`:37`). `replay_cached_response` sets the stored headers, the stored body, and the stored status. It also adds the header `Idempotent-Replayed: true` (`:89-94`).

**3. If no entry is in the cache**, the concern runs the action with `yield` (`:47`).

**4. Write the cache** if the status is 200 to 499 (`:52`). Thus the concern also stores client errors (4xx), but not server errors (5xx). A 5xx response stays retryable.

## The `rescue` block

The comment at `:41-45` gives the reason for the unusual structure. `rescue_from` handlers operate at the controller level, which is outside the `around_action`. If the action raises an error, Rails goes directly to the handler and the code after `yield` does not operate.

To prevent this, the concern calls `rescue_with_handler(error)` itself (`:49`). This makes the handler render its response. Then the flow continues to the cache write. If no handler exists, `rescue_with_handler` returns `nil` and the concern raises the error again.

## Protection against failures

- Cache read and cache write failures do not stop the request. The concern records a warning and continues (`:61-63`, `:85-87`).
- The concern does not cache a streaming response, because it cannot read the body two times (`:69-72`).
- Only the headers in `CACHED_HEADERS` go into the cache (`:7-14`) — content type, location, and the rate-limit headers.
- Entries expire after 24 hours (`TTL`, `:5`).

## One limitation

The concern has no lock. Two identical requests that arrive at the same moment both find an empty cache. Then both run the action. The design gives protection against a retry after a response, but not against two parallel requests.
