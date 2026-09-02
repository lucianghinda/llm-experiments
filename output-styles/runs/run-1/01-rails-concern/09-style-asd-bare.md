## What it does

This concern makes write requests safe to repeat. The client sends an `Idempotency-Key` header. If the client sends the same request two times, the server replays the first response. The server does not do the work again.

## When it starts

`included do ... around_action :wrap_in_idempotency`. The concern wraps every action of the controller.

The wrapper does nothing, and calls `yield`, if one of these conditions is true (line 23):
- The `Idempotency-Key` header is empty.
- The HTTP method is not POST, PATCH, or PUT.
- No API token is present in `Current`.

## The cache key

Line 56 makes the key from five parts:
- the literal `idem:`
- the account ID of the API token
- the controller path and the action name
- the request path
- the client key

Thus two accounts can use the same client key. The keys stay separate.

## A cache hit

The code also calculates a SHA256 hash of the raw request body (line 26).

If a cache entry is present, the code compares the two body hashes:
- **The hashes are different** — the code raises `Api::Error::Conflict`. The client used one key for two different bodies. This is an error.
- **The hashes are equal** — `replay_cached_response` (line 89) writes the cached headers, the cached body, and the cached status into the response. It also adds the header `Idempotent-Replayed: true`. The action does not run.

## A cache miss

The code runs the action with `yield`. The `begin/rescue` block at lines 46–50 is important. The comment at lines 41–45 gives the cause:

`rescue_from` handlers run at the controller level. That level is outside the `around_action`. Thus an exception in the action moves past line 52, and the code does not write the cache entry. To prevent this, the concern calls `rescue_with_handler(error)` itself. This dispatches the applicable `rescue_from` handler and renders the error response. If no handler is applicable, `rescue_with_handler` gives `nil` and the code raises the exception again.

## The cache write

Line 52 writes an entry only if the status is 200 to 499. This is the Stripe contract: the server caches success responses and client-error responses, but not 5xx responses. A 5xx response usually shows a temporary fault. The client must be able to try again.

`write_idempotency_entry` (line 66) has two guards:
- It stops if there is no API token.
- It stops if the response is a stream (an `Enumerator` body, or a chunked `Transfer-Encoding`). You cannot read a stream two times.

The entry holds the status, the body, an allow-list of headers (line 7), the body hash, and a timestamp. The entry expires after 24 hours.

## Failure of the cache

The read (line 61) and the write (line 85) each catch `StandardError`. They write a warning to the log. They do not raise. Thus a fault in the cache backend does not break the API. The request continues, but without the idempotency protection.

## One property to know

The code has no lock between the read (line 27) and the write (line 52). Two identical requests that come at the same time can both find an empty cache. Then both actions run. The protection is for retries in sequence, not for requests in parallel.
