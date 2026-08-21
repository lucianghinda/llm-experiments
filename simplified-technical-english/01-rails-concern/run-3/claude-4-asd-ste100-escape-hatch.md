# How `Idempotency` works

`app/controllers/concerns/idempotency.rb`

## What it does

The concern makes a write request safe to send more than one time.

The client sends an `Idempotency-Key` header with the request. The server does the work one time and keeps the response in the cache. If the client sends the same request again with the same key, the server does not do the work again. The server sends the stored response back.

This is the Stripe-style idempotency contract.

## The constants

| Constant | Value | Function |
|---|---|---|
| `WRITABLE_METHODS` | `POST`, `PATCH`, `PUT` | Only these methods get idempotent treatment. |
| `TTL` | 24 hours | A cache entry stays valid for this time. |
| `HEADER` | `Idempotency-Key` | The name of the request header. |
| `CACHED_HEADERS` | 6 header names | The concern keeps only these response headers. |

`CACHED_HEADERS` holds `Content-Type`, `Location` and the four `X-RateLimit-*` headers. The list is an allowlist, not a blocklist. Thus a replay cannot send `Set-Cookie` or another session header a second time.

## Where the concern runs

`Api::BaseController` includes the concern. The `included` block adds one callback:

```ruby
around_action :wrap_in_idempotency
```

The position of this callback in `Api::BaseController` is important:

1. `ApiAuth` adds `before_action :require_api_token`.
2. `Idempotency` adds `around_action :wrap_in_idempotency`.
3. `RateLimit` adds `before_action :enforce_rate_limit`.

Rails runs these callbacks in this order. Two results follow:

- The authentication callback runs first. Thus `Current.api_token` already has a value when the around-action starts.
- The rate limit callback runs *inside* the around-action. Thus a replay does not use a rate limit slot. The test `idempotent replay does not decrement the rate limit counter` confirms this.

## Step 1: Is this request idempotent?

```ruby
key = request.headers[HEADER]
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Three conditions must be true:

- The client sent an `Idempotency-Key` header.
- The HTTP method is `POST`, `PATCH` or `PUT`.
- An API token is authenticated.

If one condition is false, the concern calls `yield` and stops. The action then runs in the usual way, with no cache.

## Step 2: Build the cache key and the body hash

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The cache key holds five parts:

- The account id. This keeps one account separate from the other accounts. Two accounts can send the same key value. The two requests do not interfere.
- The controller path and the action name.
- The request path. Two different articles are two different paths.
- The key from the client.

Because the key holds the route and the path, the client can use one key value on more than one endpoint. The tests `same Idempotency-Key can be reused across different POST endpoints` and `... on different resource paths` show this behaviour.

The concern also makes a SHA256 hash of the raw request body:

```ruby
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

## Step 3: Read the cache

`read_idempotency_entry` reads the cache. If the read operation fails, the method writes a warning to the log and returns `nil`. A cache failure does not stop the request. The request continues as a new request.

## Step 4a: An entry exists (replay)

If an entry exists, the concern compares the two body hashes.

**The hashes are different.** The concern raises `Api::Error::Conflict`. This becomes an HTTP 409 response with the message `Idempotency-Key has already been used with a different request body.` The details field holds the key. This tells the client that it used one key for two different bodies.

**The hashes agree.** `replay_cached_response` does four operations:

```ruby
entry[:headers].each { |name, value| response.set_header(name, value) }
response.set_header("Idempotent-Replayed", "true")
self.response_body = entry[:body]
response.status = entry[:status]
```

The method then returns. It does not call `yield`. Thus the action does not run, and the rate limit callback does not run.

The `Idempotent-Replayed: true` header is the signal to the client. The header is not in `CACHED_HEADERS`, so the first response never has it.

## Step 4b: No entry exists (first request)

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

The comment in the file gives the reason for this block.

`rescue_from` handlers are at the controller level. They are *outside* the around-action. If the action raises an error, Rails leaves the around-action through that error. The code after `yield` never runs. Then the concern caches nothing.

This is a problem, because the contract must also replay 4xx responses. A validation error must give the same 422 on the second request.

To solve this, the concern catches the error itself. `rescue_with_handler` is a Rails method from `ActiveSupport::Rescuable`. It finds the matching `rescue_from` handler and runs it. The handler renders the error response and sets the status.

- If a handler runs, `rescue_with_handler` returns a value that is not false. The code continues to the cache write.
- If no handler runs, the method returns `nil`, and the concern raises the error again.

`ErrorResponder` registers `rescue_from StandardError`, so a handler is almost always available.

## Step 5: Write the cache entry

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

The concern caches 2xx, 3xx and 4xx responses. It does not cache 5xx responses. A server error is usually temporary. The client must be able to send the request again and get new work.

`write_idempotency_entry` has three guards:

1. **No API token.** The method returns.
2. **A streaming response.** If the body is an `Enumerator`, or the `Transfer-Encoding` header is `chunked`, the method writes a warning to the log and returns. You cannot read a stream two times.
3. **A cache error.** The `rescue` block writes a warning to the log. A failed write does not fail the request.

The entry is a hash with five keys:

```ruby
{ status:, body:, headers: response.headers.slice(*CACHED_HEADERS), body_hash:, created_at: }
```

The `expires_in: TTL` option removes the entry after 24 hours.

## Summary of the behaviour

| Situation | Result |
|---|---|
| No key, or a `GET`, or no token | Normal request. No cache. |
| First request with a key, 2xx | Action runs. Response goes to the cache. |
| First request with a key, 4xx | Handler renders the error. Response goes to the cache. |
| First request with a key, 5xx | Handler renders the error. No cache write. |
| Second request, same key, same body | Cached response comes back with `Idempotent-Replayed: true`. Action does not run. |
| Second request, same key, different body | 409 Conflict. |
| Same key, different account | Different cache key. Normal request. |
| Request after 24 hours | Entry is gone. Normal request. |

## Points to note

**A 429 goes into the cache.** `enforce_rate_limit` runs inside the `yield`. If the account is over its limit, the callback raises `Api::Error::RateLimited`. The rescue block handles that error, and the status becomes 429. 429 is in the range 200 to 499. Thus the concern writes the 429 to the cache. That key then replays the 429 for 24 hours, even after the rate limit window ends. The client must use a new key.

**There is no lock during the work.** The concern writes the entry only after the action ends. Two requests with the same key that arrive at the same time can both read an empty cache. Both then run the action. The window is small, but it exists.

**A failed audit log enqueue re-raises the error.** `render_api_error` ends with a call to `record_audit_log`. That call returns `nil` if the job enqueue fails. `rescue_with_handler` gives that `nil` back to the concern, and `raise unless` raises the error again. The error response is already rendered at that moment.

**`created_at` is not used.** The concern stores the value in the entry, but no code in this file reads it. Rails cache expiry uses `expires_in`, not this field.

**Cache errors are safe.** Every cache operation has a `rescue`. A cache outage removes the idempotency protection, but it does not break the API.
