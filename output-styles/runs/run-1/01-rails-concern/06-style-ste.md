`app/controllers/concerns/idempotency.rb` is a controller concern that makes write requests safe to retry. A client sends the same `Idempotency-Key` header twice; the second call returns the stored first response instead of doing the work again.

## When it runs

`included do around_action :wrap_in_idempotency end` wraps every action of the including controller. The wrapper does nothing (just `yield`) unless all three conditions hold (line 23):

1. The request has an `Idempotency-Key` header.
2. The method is `POST`, `PATCH`, or `PUT`.
3. `Current.api_token` is set — so this is API traffic, not a browser session.

## The cache key

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The key includes the account id, so one tenant cannot read or overwrite another tenant's entry. It also includes the controller, action, and path, so the same client key used on a different endpoint is a separate entry.

## First call vs. replay

The code hashes the raw request body with SHA-256 and reads the cache.

**Cache miss** — the action runs. Afterwards, if the status is 2xx, 3xx, or 4xx (`>= 200 && < 500`, line 52), the entry is written with a 24 hour TTL. It stores the status, body, body hash, and a short allow-list of headers (`Content-Type`, `Location`, and the four `X-RateLimit-*` headers). 5xx responses are not cached, so a server error can be retried for real.

**Cache hit** — two paths:

- If the stored `body_hash` differs from the current one, the same key is being reused with a different payload. That raises `Api::Error::Conflict` (a 409). This blocks a client bug where one key is reused for two different operations.
- If the hashes match, `replay_cached_response` writes the stored headers, status, and body onto the response, adds `Idempotent-Replayed: true`, and the method returns. **The action body never runs.**

## The `rescue_from` workaround

This is the subtle part (lines 41–50). `rescue_from` handlers run at the controller level, which is *outside* the `around_action`. If the action raises, the exception passes through the `around_action` and nothing after `yield` executes — so the cache write would be skipped.

Since the contract says 4xx responses should also be replayable, the concern calls `rescue_with_handler(error)` itself. That dispatches the matching `rescue_from` handler inline, which renders the error response. If a handler existed, execution continues to line 52 and the rendered 4xx status gets cached. If no handler matched, `rescue_with_handler` returns nil (falsy) and the exception is re-raised, so it reaches Rails' normal error handling.

## Failure handling

Cache problems never break the request. Both `read_idempotency_entry` and `write_idempotency_entry` rescue `StandardError`, log a warning, and continue — a read failure just means the action runs normally. Writes are also skipped for streaming responses (`Enumerator` body or `Transfer-Encoding: chunked`), because the body cannot be captured as a string.

## One gap worth knowing

There is no lock or "in progress" marker. The cache entry is written only *after* the action finishes. If two identical requests arrive at the same time, both see a cache miss and both execute the action. The concern protects against sequential retries, not concurrent duplicates. Stripe's implementation reserves the key before running the work to close this window.
