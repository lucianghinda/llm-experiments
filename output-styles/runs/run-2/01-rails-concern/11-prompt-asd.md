`app/controllers/concerns/idempotency.rb` — explanation in Simplified Technical English (ASD-STE100):

## Function

This module makes API writes safe to repeat. A client can send the same request two times. The server does the work one time only. The server sends the first answer again for the second request.

## Constants

- `WRITABLE_METHODS` — the module controls only POST, PATCH and PUT requests.
- `TTL` — the cache keeps each record for 24 hours.
- `HEADER` — the client sends the key in the `Idempotency-Key` header.
- `CACHED_HEADERS` — the module keeps only these six headers: the content type, the location, and the four rate-limit headers.

## Start

The controller that includes this module gets an `around_action`. Thus the method `wrap_in_idempotency` runs before and after each action.

## The conditions

The method reads the header key. Then it does the usual action and stops, if one of these three conditions is true:

1. The request has no key.
2. The request method is not POST, PATCH or PUT.
3. There is no API token in `Current`.

## The cache key and the body hash

The method makes a cache key. The key contains the account ID, the controller path, the action name, the request path, and the client key. Different accounts and different endpoints thus cannot get the answer of each other.

The method also calculates a SHA-256 hash of the request body.

## If a record is in the cache

The method compares the two body hashes. If the hashes are different, the client used the same key with a different body. The method then raises `Api::Error::Conflict`.

If the hashes are the same, the method sends the old answer again. `replay_cached_response` sets the kept headers, the kept body and the kept status. It also adds the header `Idempotent-Replayed: true`. The action does not run.

## If no record is in the cache

The method does the action with `yield`.

The comment in the code gives the reason for the `rescue` block. Rails does `rescue_from` at the controller level. That level is outside this `around_action`. Thus the code after `yield` does not run if the action raises an error. The module therefore calls `rescue_with_handler` itself. If a handler makes an answer, the flow continues. If there is no handler, the method raises the error again.

After that, the method writes the cache record. But it writes the record only if the status is from 200 to 499. Thus the module keeps the client errors, but it does not keep the server errors. The client can try a 5xx request again.

## The write

`write_idempotency_entry` does not write a record in two conditions:

- There is no API token.
- The answer is a stream. A stream is an `Enumerator` body, or a body with the header `Transfer-Encoding: chunked`. The module cannot read such a body two times.

If the module writes a record, the record contains the status, the body, the permitted headers, the body hash and the time. The record expires after 24 hours.

## Cache failures

The read method and the write method each have a `rescue`. If the cache does not operate correctly, the module writes a warning in the log. The request continues. Thus a cache failure does not stop the API. But be careful: if the read operation fails, the module does the action again.
