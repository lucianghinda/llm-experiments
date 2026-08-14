# How `Idempotency` works

`app/controllers/concerns/idempotency.rb` implements Stripe-style idempotency keys for the JSON API. A client sends an `Idempotency-Key` header with a write request. If the same key arrives again inside 24 hours, the API replays the stored response instead of running the action a second time. This is what makes a network timeout safe to retry: the client can resend the request without creating a duplicate article, a duplicate asset, or a duplicate charge on a plan quota.

The concern is mixed into `Api::BaseController`, so every API endpoint gets the behaviour for free.

## The constants

```ruby
WRITABLE_METHODS = %w[POST PATCH PUT].freeze
TTL = 24.hours
HEADER = "Idempotency-Key"
CACHED_HEADERS = %w[Content-Type Location X-RateLimit-Bucket X-RateLimit-Limit X-RateLimit-Remaining X-RateLimit-Reset].freeze
```

Only `POST`, `PATCH` and `PUT` are covered. `GET` and `DELETE` are left alone because they are already idempotent by HTTP semantics, so there is nothing to protect.

`CACHED_HEADERS` is an allow-list, and the fact that it is an allow-list rather than "store everything" is the interesting part. Only headers that describe the response itself get stored and replayed. Anything else, `Set-Cookie` being the obvious example, is deliberately excluded so a cached entry can never leak session state from the original request into a later replay. There is even a test asserting that `Set-Cookie` is not in the list.

## Where it hooks in

```ruby
included do
  around_action :wrap_in_idempotency
end
```

An `around_action` is the right callback here because the concern needs to run code both before the action (to check for a cached response and short-circuit) and after it (to store the response that was produced).

Callback ordering matters a lot in this file, and it comes from the include order in `Api::BaseController`:

```ruby
after_action :record_audit_log

include ApiAuth      # before_action :require_api_token
include Idempotency  # around_action :wrap_in_idempotency
include RateLimit    # before_action :enforce_rate_limit
include ErrorResponder
```

Rails runs `before` callbacks in registration order and nests `around` callbacks around everything registered after them. So the resulting nesting is:

1. `record_audit_log` (an `after_action`, so it sits outermost and runs last)
2. `require_api_token`
3. `wrap_in_idempotency`
4. `enforce_rate_limit`
5. the action itself

Two consequences fall out of that ordering. First, authentication has already run by the time the idempotency code executes, so `Current.api_token` is populated and can be used to scope the cache key. Second, rate limiting happens *inside* the around action, which means a replayed response never touches the rate limit counter. There is an integration test for exactly this: replaying a request returns the same `X-RateLimit-Remaining` value it returned the first time, and the slot it did not consume is still available to a genuinely new request.

## The guard clause

```ruby
key = request.headers[HEADER]
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Three conditions must all hold before any of this machinery engages: a key was supplied, the method is a write, and the request is authenticated. Otherwise the concern yields immediately and behaves as if it were not there. Idempotency is opt-in per request, which is how Stripe's API works too.

The `Current.api_token` check is not just defensive. Without a token there is no account to scope the cache entry to, and an unscoped key would let one caller read another caller's cached response.

## The cache key

```ruby
def idempotency_cache_key(key)
  "idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
end
```

The client-supplied key is only one of five components. The others are:

- **`account_id`**, so the same key used by two different accounts produces two independent entries. There is a dedicated cross-account test for this, and it is the security-critical part of the design.
- **`controller_path#action_name`**, so a client that reuses one key across different endpoints gets a fresh execution for each endpoint rather than a nonsensical replay.
- **`request.path`**, so the same action on two different resources (`/articles/1/text_assets` and `/articles/2/text_assets`) does not collide.

The raw client key is used verbatim rather than hashed, which is fine because it is only ever a cache key component and is never echoed back except inside the 409 error details.

## Fingerprinting the body

```ruby
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

Alongside the response, the concern stores a SHA-256 digest of the raw request body. On a cache hit it compares the digests:

```ruby
if cached[:body_hash] != body_hash
  raise Api::Error::Conflict.new(
    "Idempotency-Key has already been used with a different request body.",
    details: { idempotency_key: key }
  )
end
```

This catches a real class of client bug. If a caller reuses a key but changes the payload, they almost certainly did not mean to retry, they meant to send a new request and made a mistake. Silently replaying the old response would be worse than failing, so the API returns `409 Conflict` and tells them what happened. `request.raw_post` is used rather than parsed params so the comparison is over exactly the bytes that were sent.

## The replay path

```ruby
def replay_cached_response(entry)
  entry[:headers].each { |name, value| response.set_header(name, value) }
  response.set_header("Idempotent-Replayed", "true")
  self.response_body = entry[:body]
  response.status = entry[:status]
end
```

On a hit, the stored status, body and allow-listed headers are written back onto the response and an `Idempotent-Replayed: true` header is added so the client can tell a replay from a fresh execution. Then `wrap_in_idempotency` returns *without calling `yield`*, which is what prevents the rate limiter and the action itself from running at all.

One thing worth noticing: the `after_action :record_audit_log` sits outside the around action, so a replayed request is still written to the audit log. You get a record that the call happened, even though no work was done.

## The tricky part: caching error responses

This block carries the longest comment in the file, and it deserves it.

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end

write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

The problem being solved is a genuine Rails wrinkle. `rescue_from` handlers, declared over in `ErrorResponder`, are installed at the controller level, which is *outside* the callback chain. If the action raises a `ValidationError`, the exception propagates straight out through the around action, and every line after `yield` is skipped. The response would be rendered correctly as a 422, but nothing would ever be cached, so a retry with the same key would re-run the action and re-do the validation work.

The fix is to catch the exception here and dispatch the rescue handler manually with `rescue_with_handler`, which is the same lookup Rails would have performed itself. That method returns truthy if a handler was found and ran, and `nil` if nothing matched. So:

- If a handler ran, the response has been rendered, execution continues, and the entry gets cached with whatever status the handler produced.
- If no handler matched, `raise` re-raises the original exception and the concern gets out of the way.

In practice `ErrorResponder` registers a `rescue_from StandardError` catch-all, so in this app a handler nearly always matches. The `raise unless` branch is a correctness guard rather than a common path.

The status filter on the write is the actual policy statement:

- **2xx and 3xx** are cached. This is the ordinary success case.
- **4xx** is cached. This is the deliberate Stripe-compatible choice. A validation failure is a deterministic outcome of that exact payload, so replaying the 422 is both correct and cheaper than re-running the action. There is a test named "Idempotency-Key replay returns the original 422 without re-running the action".
- **5xx** is *not* cached. A server error might be transient (a database blip, a timed-out upstream), and caching it for 24 hours would permanently poison that key. Leaving 5xx uncached means the retry actually retries.

## Writing the entry

```ruby
def write_idempotency_entry(cache_key, body_hash)
  return unless Current.api_token

  if response.body.is_a?(Enumerator) || response.headers["Transfer-Encoding"] == "chunked"
    Rails.logger.warn("Idempotency cache write skipped for streaming response")
    return
  end

  Rails.cache.write(cache_key, { status:, body:, headers:, body_hash:, created_at: }, expires_in: TTL)
rescue StandardError => error
  Rails.logger.warn("Idempotency cache write failed: #{error.class}: #{error.message}")
end
```

Three defensive details here.

Streaming responses are skipped. Calling `response.body` on a streamed response would consume the enumerator and break the response being sent to the client, and buffering an arbitrarily large stream into the cache is not something you want anyway. Both the `Enumerator` check and the `Transfer-Encoding: chunked` check exist because the two cases can present differently.

`created_at` is stored even though `expires_in: TTL` already handles expiry. It is not used by the read path, so it is there for debugging and for any future logic that wants to know how old a replay is.

Both cache methods swallow their exceptions and log a warning. `read_idempotency_entry` returns `nil` on failure, which degrades to a cache miss and re-runs the action. `write_idempotency_entry` just logs. This is the correct trade-off for a cache: an outage in the cache backend should make idempotency stop working, not make the API stop working. The worst case is that a retry executes twice, which is exactly where you would be with no idempotency support at all.

## What it does not do

Two limitations are worth being explicit about, because they are design choices rather than oversights.

There is no in-flight locking. If two identical requests arrive concurrently, both will miss the cache, both will execute, and both will write. The concern protects against sequential retries, not against a simultaneous double-submit. A stricter implementation would insert a "processing" sentinel on first sight of a key and return `409` to concurrent duplicates.

The cached response is stored as a rendered string, so it is a snapshot rather than a live view. If the underlying record changes during the 24 hour window, a replay still returns the original body. That is the point of the contract, but it is worth knowing when reading a replayed response.
