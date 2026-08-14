# How the Idempotency concern works

## Purpose

The file `app/controllers/concerns/idempotency.rb` makes write requests safe to repeat.

A client sends a request. The network fails. The client does not know if the server did the work. The client sends the same request again.

Without protection, the server does the work two times. The account gets two articles instead of one.

With this concern, the server does the work one time. The second request gets the same response as the first request. The behaviour follows the Stripe API convention.

## Where the code runs

`Api::BaseController` includes the module. All API controllers inherit from that class.

The module adds one callback:

```ruby
included do
  around_action :wrap_in_idempotency
end
```

An `around_action` runs before the action and after the action. The word `yield` inside the method starts the action. Everything before `yield` is the check. Everything after `yield` is the save step.

The base controller includes `Idempotency` before `RateLimit`. The rate limit check is a `before_action`. Therefore the rate limit check runs inside the idempotency wrapper. This order is important. It is explained again in the replay step.

## The settings

The module defines five constants:

| Constant | Value | Function |
| --- | --- | --- |
| `WRITABLE_METHODS` | `POST`, `PATCH`, `PUT` | Only these methods change data. |
| `TTL` | 24 hours | The stored response expires after this time. |
| `HEADER` | `Idempotency-Key` | The client sends the key in this header. |
| `CACHED_HEADERS` | 6 header names | Only these headers go into the store. |

The header list contains `Content-Type`, `Location`, and the four rate limit headers. The list is an allow list. `Set-Cookie` and authentication headers stay out of the store. A replayed response cannot leak a session or a credential.

## Step 1: Decide if the request needs protection

```ruby
key = request.headers[HEADER]
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

The code needs three conditions:

1. The client sent an `Idempotency-Key` header.
2. The request method is `POST`, `PATCH`, or `PUT`.
3. An API token is active for the current request.

If one condition fails, the code calls `yield` and stops. The action runs in the normal way. No cache read happens and no cache write happens.

The feature is optional. The client decides. A client that sends no key gets no protection.

## Step 2: Build the cache key and the body fingerprint

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The cache key has five parts:

- A fixed prefix `idem`.
- The account ID. One account cannot read the stored response of another account.
- The controller and the action. The same key works again on a different endpoint.
- The request path. The same key works again on a different resource.
- The key from the header.

The code also makes a fingerprint of the request body:

```ruby
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

The fingerprint is a SHA256 hash of the raw body. The code uses the fingerprint to find a client mistake. The mistake is one key with two different bodies.

## Step 3: Read the store

```ruby
def read_idempotency_entry(cache_key)
  Rails.cache.read(cache_key)
rescue StandardError => error
  Rails.logger.warn("Idempotency cache read failed: ...")
  nil
end
```

The read has a rescue block. A cache failure writes a warning to the log and returns `nil`. A `nil` result looks like a cache miss. The request then runs in the normal way.

This is important. The cache never breaks the API. A cache failure only removes the protection for that one request.

## Step 4: A stored response exists

Two results are possible.

### Result A: The body is different

```ruby
raise Api::Error::Conflict.new(
  "Idempotency-Key has already been used with a different request body.",
  details: { idempotency_key: key }
)
```

The client used one key for two different bodies. This is a client error. The server answers with status 409.

The `raise` goes up to the controller. The `ErrorResponder` concern catches `Api::Error` and renders the JSON error body.

### Result B: The body is the same

```ruby
def replay_cached_response(entry)
  entry[:headers].each { |name, value| response.set_header(name, value) }
  response.set_header("Idempotent-Replayed", "true")
  self.response_body = entry[:body]
  response.status = entry[:status]
end
```

The code builds the old response again:

1. It copies the stored headers.
2. It adds the header `Idempotent-Replayed: true`. The client can see that the response is a copy.
3. It sets the stored body and the stored status.

The method returns before `yield`. The action never runs. No record is created. No job is queued.

The rate limit check also never runs, because that check is a `before_action` inside the wrapper. A replay does not consume quota. The stored rate limit headers show the numbers from the first request.

## Step 5: No stored response, so run the action

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

This block looks strange. The comment in the file explains the reason.

Rails runs `rescue_from` handlers at the controller level. That level is outside the `around_action`. If the action raises an error, Rails leaves the wrapper immediately. The code after `yield` never runs. The save step is lost.

A lost save step is a problem for 4xx responses. A validation error must also be idempotent. The second request must get the same 422 response.

The solution has three parts:

1. The code catches the error itself.
2. The code calls `rescue_with_handler(error)`. This method runs the correct `rescue_from` handler. The handler renders the error response. The method returns a true value.
3. If no handler exists, `rescue_with_handler` returns `nil` and the code raises the error again.

After this block the response object holds a status and a body. The status can come from a successful action or from an error handler.

## Step 6: Save the response

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

The rule is simple:

- Status 2xx, 3xx, and 4xx go into the store. These results are final. A retry must return the same answer.
- Status 5xx does not go into the store. A server error is temporary. The client must be able to retry with the same key and get real work.

The write method has three protections:

```ruby
return unless Current.api_token

if response.body.is_a?(Enumerator) || response.headers["Transfer-Encoding"] == "chunked"
  Rails.logger.warn("Idempotency cache write skipped for streaming response")
  return
end
```

1. It checks the token again.
2. It skips streaming responses. A streamed body cannot go into a cache entry, because a read of the stream consumes the stream.
3. It has a rescue block. A write failure writes a warning to the log and nothing more.

The stored entry has five fields: `status`, `body`, the allowed `headers`, the `body_hash`, and `created_at`. The entry expires after 24 hours.

## Summary of the flow

| Situation | Result |
| --- | --- |
| No key, or a `GET` request, or no token | Normal action, no cache |
| Key is new | Action runs, response saved for 24 hours |
| Key is known, body is the same | Old response returned, header `Idempotent-Replayed: true` |
| Key is known, body is different | Status 409 conflict |
| Action returns 4xx | Response saved, so the retry gets the same 4xx |
| Action returns 5xx | Response not saved, so the retry does real work |
| Cache is down | Warning in the log, normal action |

## Limits to know

- The protection is best effort. The cache can fail. The entry can expire after 24 hours.
- There is no lock during the action. Two identical requests that arrive at the same moment can both miss the cache. Both can then run the action.
- The path in the cache key is `request.path`. This value has no query string. The fingerprint uses the body only. Therefore two requests with the same path and the same body share one entry, also when the query strings are different.
- The field `created_at` goes into the entry, but this file never reads the field. The field helps during debug work.
