`Idempotency` is a controller concern. It makes a repeated write request safe. The client sends the same `Idempotency-Key` header two times. The server then gives the first response again. It does not do the work two times.

## When the concern is active

The `around_action` hook wraps every action (`idempotency.rb:17`). The guard at `idempotency.rb:23` lets the request pass through without a change if one of these conditions is true:

- The `Idempotency-Key` header is absent.
- The HTTP method is not POST, PATCH, or PUT.
- `Current.api_token` is empty. Only API requests use this function.

## The cache key

The concern makes a cache key from five parts (`idempotency.rb:56`): the account ID, the controller path, the action name, the request path, and the client key. The account ID keeps the keys of different tenants separate. Thus one client cannot read the response of a different client.

The concern also calculates a SHA-256 hash of the raw request body (`idempotency.rb:26`).

## A cache entry exists

The concern compares the body hash with the stored hash (`idempotency.rb:30`). 

- If the two hashes are different, the concern raises `Api::Error::Conflict`. The client used one key for two different requests. This is an error.
- If the two hashes are equal, `replay_cached_response` writes the stored status, body, and headers into the response (`idempotency.rb:89`). It also adds the header `Idempotent-Replayed: true`. The action does not run.

Only the six headers in `CACHED_HEADERS` are stored: the content type, the location, and the four rate-limit headers.

## No cache entry exists

The action runs (`idempotency.rb:47`). The `begin`/`rescue` block around `yield` is necessary. Rails runs `rescue_from` handlers outside the `around_action`. Therefore an exception from the action would stop all code after `yield`. The concern calls `rescue_with_handler` itself (`idempotency.rb:49`). The handler renders the error response. Control then comes back into this method. If no handler exists, the concern raises the exception again.

Then the concern writes the cache entry, but only for a status from 200 to 499 (`idempotency.rb:52`). A 5xx status is a server failure. The client must be able to try again. Client errors (4xx) are stored. This agrees with the Stripe behavior.

The entry expires after 24 hours (`TTL`).

## Failure protection

Cache read and write operations have a `rescue` (`idempotency.rb:61` and `idempotency.rb:85`). If the cache is not available, the concern writes a warning in the log and continues. The request does not fail.

The concern does not store streaming responses (`idempotency.rb:69`). It cannot read the body of an `Enumerator` two times.

## One limit

The concern has no lock for a request in progress. It writes the cache entry only after the action is complete. If two requests with the same key come at the same time, both actions can run. Stripe returns a 409 status in this condition. This code does not.
