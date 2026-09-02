Here is how `app/controllers/concerns/idempotency.rb` works.

## Purpose

It gives the API a Stripe-style `Idempotency-Key` contract: if a client retries the same write request with the same key, the server replays the first response instead of doing the work twice.

## Entry point

```ruby
included do
  around_action :wrap_in_idempotency
end
```

Every action of a controller that includes the concern is wrapped. `yield` inside the method runs the real action.

## Step 1 — decide if idempotency applies (line 23)

Three conditions must all hold:

- the request has an `Idempotency-Key` header,
- the method is `POST`, `PATCH` or `PUT` (reads and `DELETE` are skipped),
- `Current.api_token` is set (so this is an authenticated API call).

If any fails, the action just runs normally.

## Step 2 — build the cache key and body fingerprint (lines 25–27)

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The key is scoped by account, controller, action, path and the client key. So the same key used by another account, or on another endpoint, does not collide.

`body_hash` is a SHA256 of the raw request body. It is the fingerprint used to detect key reuse.

## Step 3 — cache hit (lines 29–39)

- If the stored `body_hash` differs from the current one, the client reused a key with a *different* payload. That is an error, so it raises `Api::Error::Conflict` (HTTP 409).
- Otherwise `replay_cached_response` writes the stored status, body and whitelisted headers back into the response, adds `Idempotent-Replayed: true`, and the method returns **without calling `yield`**. The action never runs.

Only the headers in `CACHED_HEADERS` are replayed — content type, `Location`, and the rate-limit headers. Everything else (cookies, request id) is regenerated per request.

## Step 4 — cache miss (lines 41–52)

This is the subtle part, and the comment explains it. `rescue_from` handlers registered in the controller run *outside* an `around_action`. So if the action raises, the exception passes straight through this method and the code after `yield` never runs — no cache entry would be written for error responses.

To avoid that, the concern dispatches the handler itself:

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

`rescue_with_handler` returns truthy when a matching `rescue_from` handler exists and ran (which renders the 4xx response). In that case the flow continues normally. If no handler matches, the exception is re-raised and behaves as before.

Then:

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

2xx, 3xx and 4xx are cached — a validation error is a stable outcome, so a retry gets the same error back. 5xx is **not** cached, so a client can retry after a server failure and get real work done.

## Step 5 — writing the entry (lines 66–87)

- Streaming responses (enumerator body or chunked transfer) are skipped, because the body cannot be read and stored.
- The entry stores status, body, whitelisted headers, the body hash and a timestamp, with a 24 hour TTL.

## Failure handling

Both `read_idempotency_entry` and `write_idempotency_entry` rescue `StandardError`, log a warning, and carry on. This is deliberate: if the cache store is down, requests still work — the app just loses the idempotency guarantee instead of returning 500s.

## Two things worth knowing

1. **No locking.** Between the cache read and the cache write there is a window. Two truly concurrent requests with the same key can both miss the cache and both execute the action. Stripe handles this with an "in progress" marker that makes the second request return 409. If concurrent retries are a real risk here, that gap needs a lock.
2. **The query string is not covered.** `request.path` excludes the query string and `raw_post` does not contain it. Two requests with the same key and body but different query parameters would replay the first response.
