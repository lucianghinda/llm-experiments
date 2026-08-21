# The Idempotency Concern

## What the code does

The file `app/controllers/concerns/idempotency.rb` holds a Rails concern.
The concern makes a write request safe to send more than one time.
The client puts a key in the `Idempotency-Key` header.
The server does the work one time only.
For each subsequent request with the same key, the server sends the first response again.

`Api::BaseController` includes this concern.
As a result, all API controllers get this behavior.

## The constants

| Constant | Value | Function |
| --- | --- | --- |
| `WRITABLE_METHODS` | POST, PATCH, PUT | The concern operates only on these HTTP methods. |
| `TTL` | 24 hours | The cache keeps each record for this time. TTL is the time to live. |
| `HEADER` | `Idempotency-Key` | The name of the header with the key. |
| `CACHED_HEADERS` | 6 header names | The concern keeps only these response headers. |

The six headers are `Content-Type`, `Location`, and the four `X-RateLimit-*` headers.

## When the concern operates

The concern adds an `around_action` callback with the name `wrap_in_idempotency`.
Rails calls this method before the controller action and after the controller action.
The word `yield` in the method starts the controller action.

The method does no special work if one of these conditions is true:

- The request has no `Idempotency-Key` header, or the header is empty.
- The HTTP method is not POST, PATCH or PUT.
- The request has no API token in `Current.api_token`.

In these conditions, the method runs the action and then stops.

## The cache key

The method makes a cache key from five parts:

1. The text `idem`.
2. The account ID of the API token.
3. The controller path and the action name.
4. The path of the request.
5. The value of the `Idempotency-Key` header.

The account ID keeps the data of each account separate.
One account cannot read the cache record of a different account.
The controller path and the request path also change the cache key.
Because of this, a client can use the same key on different endpoints.
Each endpoint gets its own cache record.

## The body hash

The method calculates a SHA256 hash of the raw body of the request.
The hash is a short value.
If the body changes, the hash also changes.
The method keeps this hash in the cache record.

## The first request

The cache has no record for the key.
The method does these steps:

1. The method runs the controller action with `yield`.
2. If the action raises an error, the method gives the error to `rescue_with_handler`.
3. `rescue_with_handler` finds the `rescue_from` handler in `ErrorResponder` and makes an error response.
4. If Rails has no handler for the error, the method raises the error again.
5. The method reads the status of the response.
6. If the status is 200 to 499, the method writes a record to the cache.

The comment in the code tells you why step 2 is necessary.
Rails runs the `rescue_from` handlers at the controller level.
This level is outside the `around_action` callback.
Thus the code after `yield` does not run when the action raises an error.
The method calls the handler itself to prevent this problem.

The method does not write a record for a status of 500 or more.
A server error can be temporary.
The client can send the same request again and get new work.

The cache record holds five fields:

- `status`: the status of the response.
- `body`: the full body of the response.
- `headers`: only the headers in `CACHED_HEADERS`.
- `body_hash`: the hash of the request body.
- `created_at`: the time of the write.

The record expires after 24 hours.

## The subsequent request

The cache has a record for the key.
The method compares the hash of the new body with the hash in the record.

If the two hashes are different, the method raises `Api::Error::Conflict`.
The message tells the client that the key already has a different request body.
This behavior prevents the accidental use of one key for two different operations.

If the two hashes are the same, the method sends the old response again.
The method does these four steps in `replay_cached_response`:

1. It sets each header from the record on the response.
2. It sets the header `Idempotent-Replayed` to `true`.
3. It sets the body of the response to the body in the record.
4. It sets the status of the response to the status in the record.

The method does not run the controller action.
The header `Idempotent-Replayed` tells the client that this response is a copy.

## Protection against cache failures

`read_idempotency_entry` and `write_idempotency_entry` catch all standard errors.
Each method writes a warning in the log and then continues.
As a result, a failure of the cache does not stop the API request.

If the read fails, the method gets `nil` and runs the action as usual.
If the write fails, the client loses the protection for that key only.

## Responses in parts

Some responses go to the client in small parts.
`write_idempotency_entry` finds these responses with two tests:

- The body of the response is an `Enumerator`.
- The header `Transfer-Encoding` has the value `chunked`.

For these responses, the method writes a warning in the log and writes no record.
The full body is not in the memory, so the cache cannot keep it.

The write method also tests `Current.api_token` again before it writes.

## Limits

The method writes the cache record after the action is complete.
The concern has no lock.
Because of this, two identical requests at the same time can both run the action.

The replay contains only the six headers in `CACHED_HEADERS`.
The client does not get the other headers of the first response.
