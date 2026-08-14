# How `Idempotency` works

`app/controllers/concerns/idempotency.rb` is a controller concern that gives the public API Stripe-style idempotent writes. A client sends an `Idempotency-Key` header with a write request. If the same key arrives again within 24 hours, the API replays the stored response instead of running the action a second time. This is what makes it safe for a client to retry a `POST` after a timeout without creating two records.

## The configuration at the top

```ruby
WRITABLE_METHODS = %w[POST PATCH PUT].freeze
TTL = 24.hours
HEADER = "Idempotency-Key"
CACHED_HEADERS = %w[
  Content-Type
  Location
  X-RateLimit-Bucket
  X-RateLimit-Limit
  X-RateLimit-Remaining
  X-RateLimit-Reset
].freeze
```

Four decisions are encoded here. Only mutating verbs are protected, because `GET` and `DELETE` are already idempotent by definition. Entries live for 24 hours. The header name matches the convention clients already know from Stripe. And only an explicit allow list of response headers is stored, which keeps session headers such as `Set-Cookie` out of the cache. That last point matters: a replayed entry is served to whoever presents the key, so caching a `Set-Cookie` would leak one caller's session to another.

## Where it sits in the callback chain

```ruby
included do
  around_action :wrap_in_idempotency
end
```

`Api::BaseController` includes the concerns in a deliberate order:

```ruby
include ApiAuth       # before_action :require_api_token
include Idempotency   # around_action :wrap_in_idempotency
include RateLimit     # before_action :enforce_rate_limit
include ErrorResponder
```

Rails runs before and around callbacks in registration order, so authentication happens before the around block opens. That is why `Current.api_token` can be relied on inside the concern. Rate limiting is registered after the around block, so it runs *inside* it. The consequence is that a replayed response never reaches `enforce_rate_limit`, so a retry does not consume quota. That is also why the rate limit headers are in `CACHED_HEADERS`: since the live rate limit callback never runs on a replay, the headers from the original response are what the client gets back.

The audit log `after_action` in `Api::BaseController` is registered before all of these includes, which puts it outside the around block. Replayed responses are therefore still audited, with the replayed status.

## The guard clause

```ruby
key = request.headers[HEADER]
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Three conditions must hold before any of the machinery engages: a key was sent, the verb mutates state, and the request is authenticated. Otherwise the action runs normally. The token requirement is not just a nil guard, it is what makes the cache key tenant-scoped a few lines later.

## The cache key and the body fingerprint

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The key the client chooses is only one component. It is namespaced by account, by controller and action, and by request path. Two accounts can use the identical key string without colliding, and the same key reused against a different endpoint is treated as a different operation.

Alongside it, the concern fingerprints the request body:

```ruby
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

This hash is stored with the entry and is the basis of the conflict check below.

## Path 1: a cache hit

```ruby
if cached
  if cached[:body_hash] != body_hash
    raise Api::Error::Conflict.new(
      "Idempotency-Key has already been used with a different request body.",
      details: { idempotency_key: key }
    )
  end

  replay_cached_response(cached)
  return
end
```

Same key and same body means the client is retrying. The stored response is replayed and the action never executes, so no side effects are repeated.

Same key but a different body means the client made a mistake, most likely reusing a key it should have rotated. Returning the old response would silently discard the new payload, so the concern raises `Api::Error::Conflict`, which `ErrorResponder` renders as a 409.

The replay itself is a manual reconstruction of the response object:

```ruby
def replay_cached_response(entry)
  entry[:headers].each { |name, value| response.set_header(name, value) }
  response.set_header("Idempotent-Replayed", "true")
  self.response_body = entry[:body]
  response.status = entry[:status]
end
```

Setting `self.response_body` marks the response as rendered, so Rails does not complain about a missing template and does not continue into the action. The `Idempotent-Replayed: true` header is the signal that lets a client tell a fresh result apart from a cached one, which is useful when debugging.

## Path 2: a cache miss

This is the most subtle part of the file, and the comment in the source explains why it is written this way:

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end

write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

The problem is a layering one. `rescue_from` handlers registered by `ErrorResponder` are installed at the controller level, which is outside this `around_action`. If the action raises, the exception propagates out of the around block first, and everything after `yield` is skipped. The cache write would never happen, and a request that produced a clean 422 would not be replayable.

So the concern dispatches the rescue handler itself. `rescue_with_handler` is the Rails API behind `rescue_from`: it looks up a registered handler for the exception, calls it, and returns the exception when one was found, or `nil` when none was. Since `ErrorResponder` registers `rescue_from StandardError`, essentially every application error is handled here, the handler renders the error payload, and control returns normally so the code after the `begin` block can run. `raise unless ...` re-raises anything with no registered handler, which preserves normal Rails behavior for the cases this concern cannot render.

The write condition, `status >= 200 && status < 500`, is the replay contract in one line. Success responses and 4xx client errors are cached, because both are deterministic outcomes the client should see again on retry. 5xx responses are deliberately not cached, because a server error is exactly the case where the client *should* be able to retry and get a real attempt.

## Writing the entry

```ruby
if response.body.is_a?(Enumerator) || response.headers["Transfer-Encoding"] == "chunked"
  Rails.logger.warn("Idempotency cache write skipped for streaming response")
  return
end
```

Streaming responses are skipped. Reading an `Enumerator` body to store it would consume the stream that is being sent to the client, and a chunked response has no single body value to snapshot. The concern degrades to non-idempotent behavior and logs a warning rather than corrupting the response.

Everything else is stored as a hash with the status, body, filtered headers, body fingerprint, and a `created_at` timestamp, under the 24 hour TTL.

## Failure handling

Both cache operations are wrapped:

```ruby
rescue StandardError => error
  Rails.logger.warn("Idempotency cache read failed: #{error.class}: #{error.message}")
  nil
```

The concern fails open. If the cache backend is unavailable, a read returns `nil` and the request is treated as a first attempt, and a failed write logs a warning without breaking the response that was already produced. The tradeoff is explicit: a cache outage costs you idempotency guarantees, but it does not cost you availability.

## Limitations worth knowing

There is no in-flight lock. Two concurrent requests carrying the same key both miss the cache and both execute the action, because the entry is only written after the first one finishes. This protects against sequential retries, which is the common case, but not against a client firing duplicates in parallel. Stripe's implementation takes a lock on the key and returns a 409 to the second request while the first is running.

The stored `created_at` is written but never read anywhere in this file. It is available for debugging or for a future policy, such as reporting how old a replayed response is.

Finally, the concern is keyed on `request.path`, not on the resolved route pattern. Two paths that hit the same action with different resource IDs are correctly treated as different operations, which is what you want, but it also means a client cannot reuse one key across a redirect to a different path.
