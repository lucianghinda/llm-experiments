## What the file does

`Idempotency` is a controller concern. It makes a write request safe to repeat. The client sends an `Idempotency-Key` header. If the client sends the same request two times, the server does the work one time. The second request gets the stored response.

## When it becomes active

`app/controllers/concerns/idempotency.rb:21-23` — the `around_action` does nothing and yields immediately, unless all three conditions are true:

1. The request has an `Idempotency-Key` header.
2. The method is POST, PATCH, or PUT.
3. `Current.api_token` is set, thus the caller is an API client.

## The cache key

`idempotency_cache_key` (line 55) builds this string:

```
idem:<account_id>:<controller#action>:<request.path>:<key>
```

The account ID is part of the key. Thus one account cannot read the response of a different account. The controller, the action, and the path are also part of the key. Thus the same key on a different endpoint does not collide.

## The two paths

**Cache hit** (lines 29-39). The concern compares a SHA256 hash of the request body with the stored hash.

- If the hashes are different, it raises `Api::Error::Conflict`. This prevents a client from using one key for two different requests.
- If the hashes are equal, `replay_cached_response` writes the stored status, the stored body, and the stored headers to the response. It also adds `Idempotent-Replayed: true`. The action does not run.

**Cache miss** (lines 46-52). The concern yields, thus the action runs. Then it stores the response.

## The `rescue_with_handler` part

This is the least obvious code (lines 41-50). Rails `rescue_from` handlers run at the controller level, outside the `around_action`. If the action raises, control leaves the `around_action` immediately. The code after `yield` does not run, and nothing goes into the cache.

The concern must cache 4xx responses, because a repeated bad request must give the same error. Thus it calls `rescue_with_handler(error)` itself. This runs the applicable `rescue_from` handler, which renders the error response. Control then continues to line 52 and the entry goes into the cache. If no handler exists, `rescue_with_handler` returns nil and the code re-raises the exception.

## What it stores and what it does not store

Line 52 caches responses with a status from 200 to 499. It does not cache 5xx responses. Thus the client can retry after a server failure.

`write_idempotency_entry` (line 66) refuses to store a streaming response, because the body is an `Enumerator` and reading it would consume it. It stores only the six headers in `CACHED_HEADERS`. Other headers are lost on a replay.

Both the read and the write have a `rescue StandardError`. They write a warning to the log and continue. Thus a cache failure does not break the request. The entry expires after 24 hours (`TTL`).

## Two properties to know

- **No lock exists.** Two identical requests that arrive at the same time both find an empty cache. Both run the action. The concern prevents a repeat, but it does not prevent a race. A stronger design writes an "in progress" marker before the yield.
- **The query string is not part of the identity.** `request.path` does not include the query string, and `body_hash` uses only `request.raw_post`. Thus `POST /things?mode=a` and `POST /things?mode=b` with the same key and the same body replay the first response.
