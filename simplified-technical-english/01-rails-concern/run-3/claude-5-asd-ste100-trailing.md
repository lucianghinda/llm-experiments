# The Idempotency concern

File: `app/controllers/concerns/idempotency.rb`

## 1. Function

The `Idempotency` module prevents duplicate work from repeated API requests.

A client sends a write request with the `Idempotency-Key` header. The first
request runs the controller action. A second request with the same key does
not run the action again. The module sends the first response again from the
cache.

`Api::BaseController` includes this module. Thus all API controllers get this
function.

## 2. Constants

The module has four constants:

- `WRITABLE_METHODS` — the module protects only `POST`, `PATCH` and `PUT`
  requests.
- `TTL` — the cache keeps each entry for 24 hours.
- `HEADER` — the name of the request header is `Idempotency-Key`.
- `CACHED_HEADERS` — the module keeps only six response headers:
  `Content-Type`, `Location` and the four `X-RateLimit-*` headers.

## 3. Where the code runs

```ruby
included do
  around_action :wrap_in_idempotency
end
```

Rails runs `wrap_in_idempotency` around each action of the controller. The
method controls when the action runs. The method can also replace the
response.

## 4. The main method: `wrap_in_idempotency`

### Step 1 — Examine the request

The method reads the key from the request header. Then the method calls
`yield` immediately, and does no more work, if one of these conditions is
true:

- the header is empty;
- the HTTP method is not `POST`, `PATCH` or `PUT`;
- `Current.api_token` is empty.

`yield` runs the usual controller action. Thus a read request or a request
without a key goes through the module with no change.

### Step 2 — Make the cache key and the body hash

The cache key has this form:

`idem:<account id>:<controller path>#<action name>:<request path>:<key>`

The key contains the account, the controller, the action and the path.
Therefore the same client key on a different endpoint makes a different
cache entry. The account in the key also prevents access between accounts.

The method also makes a SHA256 hash of the raw request body. This hash shows
if the new body is the same as the first body.

### Step 3 — Look for a cache entry

The method reads the cache entry. If an entry is present, the method compares
the two body hashes:

- If the hashes are different, the method raises `Api::Error::Conflict`. The
  client receives status 409. The message tells the client that the key is
  already in use with a different body.
- If the hashes are the same, the method sends the old response again. The
  controller action does not run.

### Step 4 — Run the action

If no entry is present, the method runs the action in a `begin`/`rescue`
block:

```ruby
begin
  yield
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

The comment in the code gives the reason for this block. Rails runs the
`rescue_from` handlers at the controller level, outside this `around_action`.
Therefore an error from the action stops all code after `yield`, and the
module cannot write the cache entry. To prevent this, the method calls the
handler itself with `rescue_with_handler`. If no handler applies to the
error, the method raises the error again.

Note: `ErrorResponder` registers a handler for `StandardError`. Thus a
handler is always applicable in this application, and the method almost never
raises the error again.

### Step 5 — Write the cache entry

```ruby
write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
```

The method writes the entry only for a status from 200 to 499. Thus the module
keeps a success response and also a client error response, for example a 422.
The module does not keep a server error (5xx). The client can send the request
again after a server error.

## 5. The private methods

### `idempotency_cache_key`

This method makes the cache key string. It uses the account ID, the controller
path, the action name, the request path and the client key.

### `read_idempotency_entry`

This method reads the entry from `Rails.cache`. If the read fails, the method
writes a warning in the log and returns `nil`. Thus a cache failure does not
stop the request. The request continues as a usual request.

### `write_idempotency_entry`

The method does not write an entry in these two conditions:

- `Current.api_token` is empty;
- the response body is an `Enumerator`, or the `Transfer-Encoding` header is
  `chunked`. This is a response in parts. The module cannot keep it, and it
  writes a warning in the log.

If the method writes an entry, the entry contains five fields:

- `status` — the HTTP status of the response;
- `body` — the full body of the response;
- `headers` — only the headers in `CACHED_HEADERS`;
- `body_hash` — the SHA256 hash of the request body;
- `created_at` — the time of the write.

The entry expires after 24 hours. If the write fails, the method writes a
warning in the log. The request continues.

### `replay_cached_response`

This method changes the current response into a copy of the old response. The
method does four steps:

1. Set each header from the cache entry.
2. Set the header `Idempotent-Replayed` to `true`. Thus the client can see
   that this response is a copy.
3. Set the response body from the cache entry.
4. Set the response status from the cache entry.

## 6. Summary of the flow

| Condition | Result |
| --- | --- |
| No key, or a read method, or no API token | The action runs. The module writes nothing. |
| A key, and no cache entry | The action runs. The module keeps the response if the status is 200 to 499. |
| A key, an entry, and the same body | The module sends the old response, with `Idempotent-Replayed: true`. |
| A key, an entry, and a different body | The module raises `Api::Error::Conflict` (status 409). |

## 7. Limits

- The module writes the entry only after the action is complete. There is no
  lock. Two requests with the same key at the same time can both run the
  action.
- The module sends again only the six headers in `CACHED_HEADERS`. All other
  headers of the old response are lost.
- The module keeps the full response body in the cache. A large body makes a
  large cache entry.
- The entry contains the field `created_at`, but no code in this file reads
  this field.
