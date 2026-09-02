## What it does

This concern makes API write requests safe to send again. If the client sends the same request two times, the server does the work one time only. The second request gets the first response back from the cache.

## Flow, step by step

**1. Decide if the guard applies** (`idempotency.rb:21-23`)

The `around_action` wraps every action. It does nothing and gives control to the action, unless all three conditions are true:
- The request has an `Idempotency-Key` header.
- The method is POST, PATCH, or PUT.
- An API token is present in `Current`.

**2. Calculate the cache key and the body hash** (`idempotency.rb:25-26`)

The cache key includes the account ID, the controller, the action, the path, and the client key. Thus two accounts cannot read the entries of each other. The body hash is a SHA256 digest of the raw request body.

**3. If an entry is in the cache** (`idempotency.rb:29-39`)

- If the body hash is different, the code raises `Api::Error::Conflict`. This tells the client that it used the same key with different data.
- If the body hash agrees, the code replays the cached response. It does not run the action.

**4. If no entry is in the cache** (`idempotency.rb:46-52`)

The code runs the action inside a `begin/rescue`. This is necessary because `rescue_from` operates at the controller level, outside the `around_action`. Without this block, an exception in the action stops all code after `yield`. Then the cache write does not occur.

So the concern calls `rescue_with_handler(error)` itself:
- If a handler exists, it renders the error response. Execution continues.
- If no handler exists, the code raises the error again.

**5. Write the cache entry** (`idempotency.rb:52`)

The code caches the response for status codes 200 to 499. It caches 4xx errors, because the same bad request must give the same error. It does not cache 5xx errors, because the client must be able to try again after a server failure.

## The helper methods

| Method | Function |
|---|---|
| `read_idempotency_entry` | Reads the cache. If the cache fails, it writes a warning and returns `nil`. The request continues as usual. |
| `write_idempotency_entry` | Stores status, body, a small set of headers, the body hash, and the time. The TTL is 24 hours. It skips streaming responses, because you cannot read an `Enumerator` body two times. Cache failures are also non-fatal. |
| `replay_cached_response` | Sets the cached headers and body on the response. It adds `Idempotent-Replayed: true`, so the client can identify a replay. |

The concern only caches a short list of headers (`CACHED_HEADERS`). This prevents replay of headers that must stay unique, for example `Set-Cookie` or `ETag`.

## One limit to know

There is no lock. If two identical requests arrive at the same time, both find an empty cache. Both then run the action. The last response to complete wins the cache entry. A Stripe-type implementation puts a "in progress" marker in the cache first, and returns 409 to the second request.
