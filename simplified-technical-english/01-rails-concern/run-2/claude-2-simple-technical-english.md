# The Idempotency concern

## What the code does

The `Idempotency` module makes an API request safe to repeat.

A client sends a request. The network fails. The client does not know if the server got the request.
The client sends the same request again. Without this code, the server does the work twice.

This module stops the second run. It sends back the first answer instead.

The client controls this. It puts a header on the request. The header is `Idempotency-Key`.
The value is any string the client picks.

## Where the code runs

```ruby
included do
  around_action :wrap_in_idempotency
end
```

`ActiveSupport::Concern` lets a controller include this module.
When a controller includes it, Rails adds an `around_action` callback.

An `around_action` runs before the controller action and after it.
The method gets a block. The block is the action. The method calls `yield` to run the action.
The method can also choose not to call `yield`. Then the action never runs.
This is the whole trick of the module.

## The constants

```ruby
WRITABLE_METHODS = %w[POST PATCH PUT].freeze
TTL = 24.hours
HEADER = "Idempotency-Key"
```

`WRITABLE_METHODS` lists the HTTP methods that change data.
`GET` and `DELETE` are not in the list. A `GET` request does not change data, so a repeat is safe.

`TTL` is the life of a saved answer. The answer stays in the cache for 24 hours. Then it goes away.

`CACHED_HEADERS` lists six response headers. The code saves only these headers:

- `Content-Type`
- `Location`
- the four `X-RateLimit-*` headers

The code does not save other headers. It does not save cookies. It does not save `Set-Cookie`.

## Step 1: decide if the rule applies

```ruby
key = request.headers[HEADER]
return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token
```

Three conditions must all be true:

1. The request has an `Idempotency-Key` header, and the header is not empty.
2. The HTTP method is `POST`, `PATCH` or `PUT`.
3. `Current.api_token` holds a token.

If one condition is false, the code calls `yield` and stops. The action runs in the normal way.
No cache read happens. No cache write happens.

`Current.api_token` comes from `Current`, an `ActiveSupport::CurrentAttributes` class.
Some other code sets the token when it checks the API key.
So this module works only for API requests with a token. It does not work for a browser session.

## Step 2: build the cache key

```ruby
"idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
```

The cache key has five parts:

| Part | Reason |
|---|---|
| `account_id` | One account cannot read the answer of another account. |
| `controller_path#action_name` | The same key on a different action is a different entry. |
| `request.path` | The same action on a different record is a different entry. |
| the client key | The value the client chose. |

The `account_id` part is the important one. It is the tenant boundary.
Two clients can pick the same key value. They still get two different cache entries.

## Step 3: hash the request body

```ruby
body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
```

`request.raw_post` is the raw body of the request.
The code makes a SHA256 hash of it. The hash is a short string.

The code saves this hash with the answer. It uses the hash later, in step 4.

## Step 4: look for a saved answer

```ruby
cached = read_idempotency_entry(cache_key)
```

The code reads the cache. Two results are possible.

### Result A: an entry exists

The code compares the two hashes.

**If the hashes are different**, the client reused a key with a new body.
This is a client mistake. The code raises `Api::Error::Conflict`:

```ruby
raise Api::Error::Conflict.new(
  "Idempotency-Key has already been used with a different request body.",
  details: { idempotency_key: key }
)
```

The action does not run. The client gets an error.
This is a safety rule. It stops the client from getting the wrong answer by accident.

**If the hashes are the same**, this is a true repeat. The code replays the old answer:

```ruby
def replay_cached_response(entry)
  entry[:headers].each { |name, value| response.set_header(name, value) }
  response.set_header("Idempotent-Replayed", "true")
  self.response_body = entry[:body]
  response.status = entry[:status]
end
```

The method writes the saved headers, the saved body and the saved status.
It adds one more header, `Idempotent-Replayed: true`.
The client can read this header. It then knows the answer is old and not new.

Then `wrap_in_idempotency` does `return`. It never calls `yield`.
So the controller action never runs. No record is created. No email is sent. No money moves.

### Result B: no entry exists

This is the first time the server sees this key. The code goes on to step 5.

## Step 5: run the action and catch errors

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

This block is the hardest part of the file. The comment above it gives the reason.

Rails has `rescue_from`. In this application, `ErrorResponder` registers the handlers.
A handler catches the error and renders a JSON error response.

But `rescue_from` works at the controller level. It sits **outside** the `around_action`.
So when the action raises, the error goes past this method.
Ruby leaves the method at the `yield` line. The code after `yield` never runs.
That means the cache write never runs.

The team wants the same behaviour as Stripe. Stripe also replays a `4xx` answer.
A client that repeats a bad request must get the same error back, not a new one.

So the module catches the error itself.
`rescue_with_handler` is a Rails method. It looks for a `rescue_from` handler for this error class.

- If a handler exists, Rails runs it. The handler renders the error response.
  `rescue_with_handler` returns a true value. The code does not re-raise.
  The method continues, so the code after the `begin` block runs.
- If no handler exists, `rescue_with_handler` returns `nil`.
  `raise` runs and sends the error up. Rails then deals with it in the normal way.

In practice `ErrorResponder` registers a handler for `StandardError`.
So almost every error finds a handler here.

## Step 6: decide whether to save the answer

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

The code saves the answer only for a status from 200 to 499.

- `2xx` success is saved. A repeat gets the same success answer.
- `4xx` client error is saved. A repeat gets the same error answer.
- `5xx` server error is **not** saved. The server had a fault.
  The client can send the request again and get a real new try.

Note that `1xx` is not saved either, because the test starts at 200.

## Step 7: write to the cache

```ruby
Rails.cache.write(
  cache_key,
  { status:, body:, headers:, body_hash:, created_at: },
  expires_in: TTL
)
```

The method saves five fields: the status, the body, the six chosen headers, the body hash and the time.
The entry lives for 24 hours.

Two guards run first.

The first guard checks the token again:

```ruby
return unless Current.api_token
```

The second guard checks for a streaming response:

```ruby
if response.body.is_a?(Enumerator) || response.headers["Transfer-Encoding"] == "chunked"
  Rails.logger.warn("Idempotency cache write skipped for streaming response")
  return
end
```

A streaming body is not a string. It is an `Enumerator`, and the code can read it only one time.
If the code read it here, the client would get nothing.
So the module writes a warning to the log and saves nothing.
A streaming action is never idempotent in this system.

## Cache faults do not break the request

Both cache methods catch every `StandardError`:

```ruby
rescue StandardError => error
  Rails.logger.warn("Idempotency cache read failed: ...")
  nil
```

If Redis is down, or the cache is slow, the module does not fail the request.
It writes a warning to the log and continues.

- A failed read returns `nil`. The code treats the request as new. The action runs.
- A failed write does nothing. The next repeat runs the action again.

This is a deliberate trade. The module gives up its guarantee to keep the API up.
The design treats idempotency as a help, not as a hard promise.

## What the module does not do

The module has no lock. Two identical requests can arrive at the same moment.
Both read the cache. Both find nothing. Both run the action. Both write the same key.
The work happens two times.

A stronger design writes a "in progress" marker before the action runs.
A second request then sees the marker and gets a `409`. This module does not do that.
It protects against a **later** repeat, not against two requests at the same time.

The module also trusts the body hash to identify the request. It does not hash the query string
or the headers. The path is in the cache key, so the path is covered.

## Summary of the flow

1. No key, or a read method, or no token: run the action in the normal way.
2. A key with a saved answer and the same body: send the old answer, and do not run the action.
3. A key with a saved answer and a different body: raise a conflict error.
4. A key with no saved answer: run the action, catch any error, render it, and save the answer if the status is 200 to 499.
