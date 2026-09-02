`app/controllers/concerns/idempotency.rb` is a controller concern. It makes API write requests safe to repeat. If a client sends the same request two times, the server does the work one time only. The second request gets the stored answer.

## How the controller uses it

A controller includes the module. The `included` block then adds an `around_action` (line 17). The method `wrap_in_idempotency` runs before and after every action of that controller.

## Step 1 — the guard

Line 23 lets the request go through without any control if one of these conditions is true:

- The request has no `Idempotency-Key` header.
- The HTTP method is not POST, PATCH, or PUT (line 4).
- There is no API token in `Current`.

Thus the concern controls API writes only. It does not control reads or browser sessions.

## Step 2 — the cache key and the body hash

The cache key (line 56) contains five parts: the account ID of the token, the controller and action, the request path, and the client key. The account ID keeps the entries of different accounts apart.

Line 26 makes a SHA-256 hash of the raw request body. The concern stores this hash with the response.

## Step 3 — a hit in the cache

If the cache has an entry (line 29):

- If the body hash is different, the concern raises `Api::Error::Conflict` (lines 30–35). The client used the same key for a different request. This is an error.
- If the body hash is the same, `replay_cached_response` (lines 89–94) writes the stored status, body, and headers into the response. It also adds the header `Idempotent-Replayed: true`. The action does not run.

## Step 4 — a miss in the cache

The concern calls `yield` and the action runs (line 47).

The `begin`/`rescue` block around the `yield` is not usual, and the comment on lines 41–45 gives the reason. Rails runs `rescue_from` handlers at the controller level, outside the `around_action`. Therefore an exception in the action would go past this method, and the code after the `yield` would not run. To prevent this, the concern calls `rescue_with_handler(error)` itself (line 49). If a handler exists, the handler makes the error response, and control comes back to line 52. If no handler exists, `rescue_with_handler` returns `nil` and the concern raises the error again.

## Step 5 — the write to the cache

Line 52 stores the response if the status is from 200 to 499. This is the Stripe contract: the concern stores the successful responses and the client errors, but not the 5xx server errors. A 5xx status is usually temporary, thus the client must be able to try again.

`write_idempotency_entry` (lines 66–87) does not store streaming responses (line 69), because it is not possible to read such a body two times. It stores the status, the body, an allowed list of headers (lines 7–14), the body hash, and a timestamp. The entry expires after 24 hours (line 5).

The cache reads and writes have a `rescue` (lines 61 and 85). If the cache is not available, the concern writes a warning in the log and continues. Thus a cache failure does not stop the API. The result is a loss of the protection only.

## One risk to know

The concern has no lock for requests in progress. If two requests with the same key arrive at the same time, both find an empty cache, and both actions run. The concern prevents a repeated request that comes later; it does not prevent a parallel repeated request. A lock on the cache key, or a unique index in the database, is necessary for full protection.
