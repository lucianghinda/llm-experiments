# The Idempotency Concern

## 1. Function of the module

`Idempotency` is a Rails controller concern. It stops the same write operation from a second execution.

A client can send the same request two times. The module then sends the first response again. The controller action does not operate a second time.

## 2. The constants

The module has 4 constants:

- `WRITABLE_METHODS` holds the 3 HTTP methods POST, PATCH, and PUT.
- `TTL` is 24 hours. A cache entry stays in the cache for this time.
- `HEADER` is the text `Idempotency-Key`. This is the name of the request header.
- `CACHED_HEADERS` holds 6 response header names. These names are `Content-Type`, `Location`, and the 4 `X-RateLimit-*` names.

## 3. Installation in a controller

The `included do` block adds an `around_action` callback to the controller. The callback is the `wrap_in_idempotency` method.

An `around_action` callback operates before the controller action and after the controller action. The `yield` keyword shows the position of the controller action.

## 4. The 3 conditions

The method reads the `Idempotency-Key` header from the request. Then the method examines 3 conditions:

1. The header has a value.
2. The HTTP method is POST, PATCH, or PUT.
3. `Current.api_token` has a value.

If one condition is not true, the method calls `yield` and does no more work. The request then operates in the normal manner.

## 5. The cache key and the body hash

The `idempotency_cache_key` method makes a cache key from 5 parts:

1. The text `idem`.
2. The account ID from the API token.
3. The controller path and the action name.
4. The path of the request.
5. The value of the header.

The account ID keeps the entries of one account away from the entries of a different account. The controller path, the action name, and the request path keep the entries of one endpoint away from the entries of a different endpoint.

The method also makes a SHA256 hash of the raw request body. This hash is a short record of the content of the body.

## 6. Procedure when the cache has an entry

The `read_idempotency_entry` method reads the cache. If the cache has an entry, the module compares the two hashes.

If the hash in the entry is different from the new hash, the module raises `Api::Error::Conflict`. This tells the client that it used the same key with a different body. The controller action does not operate.

If the two hashes are the same, the `replay_cached_response` method sends the stored response again. This method does 4 steps:

1. It sets each stored header on the response.
2. It sets the header `Idempotent-Replayed` to `true`.
3. It sets the stored body.
4. It sets the stored status.

The controller action does not operate.

## 7. Procedure when the cache is empty

If the cache has no entry, the method calls `yield`. The controller action then operates.

The `rescue_from` handlers of the controller operate outside of the `around_action`. So an error in the action stops all the code after `yield`. The module would not write a cache entry for an error response.

To prevent this condition, the method puts `yield` in a `begin`/`rescue` block. In the `rescue` part, the method calls `rescue_with_handler` with the error. If a handler is available, the handler makes the response and the method continues. If no handler is available, the method raises the error again.

This gives the same behavior as the Stripe API. The module stores a 4xx response and can send it again.

## 8. The write of the cache entry

After the action, the module writes a cache entry only if the response status is more than 199 and less than 500. So:

- The module stores 2xx responses and 4xx responses.
- The module does not store 5xx responses. The client can try again after a server error.

The `write_idempotency_entry` method does no work in 2 conditions:

1. `Current.api_token` has no value.
2. The response body is an `Enumerator`, or the header `Transfer-Encoding` has the value `chunked`. This response is a stream. The method writes a warning to the log.

In all other conditions, the method writes a Hash to the Rails cache. The Hash has 5 keys: `status`, `body`, `headers`, `body_hash`, and `created_at`. The `headers` key holds only the 6 names from `CACHED_HEADERS`. The entry stays in the cache for 24 hours.

## 9. Errors in the cache

The read method and the write method each have a `rescue StandardError` part.

If the read operation fails, the method writes a warning to the log and gives `nil`. The module then does the work as if the cache were empty.

If the write operation fails, the method writes a warning to the log.

So a failure of the cache does not stop the request. The idempotency function stops, but the API continues to operate.

## 10. Summary of the sequence

1. Read the `Idempotency-Key` header.
2. If the 3 conditions are not true, do the normal action and stop.
3. Make the cache key. Make the hash of the body.
4. Read the cache entry for the key.
5. If an entry is available and the hashes are different, raise a conflict error.
6. If an entry is available and the hashes are the same, send the stored response again.
7. If no entry is available, do the controller action.
8. If the action raises an error, let the controller handler make the response.
9. If the status is more than 199 and less than 500, store the response in the cache.
