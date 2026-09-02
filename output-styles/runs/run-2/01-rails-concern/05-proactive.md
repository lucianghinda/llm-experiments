The MCP `rails_*` tools aren't connected here and the CLI fallback needs approval, so this is from the file itself.

## What it does

`Idempotency` implements Stripe-style idempotent writes for the API: a client sends an `Idempotency-Key` header, and if it retries the same request, it gets the *stored* response back instead of the action running a second time.

## Flow

**1. Guard (`idempotency.rb:23`)** — the whole thing is a no-op unless all three hold: a key is present, the method is `POST`/`PATCH`/`PUT`, and `Current.api_token` is set (i.e. an authenticated API request, not a browser session). Otherwise it just `yield`s.

**2. Cache key (`:56`)** — `idem:<account_id>:<controller#action>:<path>:<key>`. Scoping by account means keys can't collide across tenants; scoping by action + path means reusing one key against a different endpoint is treated as a different request rather than a false replay.

**3. Body fingerprint (`:26`)** — SHA256 of the raw request body, stored alongside the response.

**4. Cache hit (`:29-39`)** — two branches:
- Body hash differs → `Api::Error::Conflict` (409). This is the "you reused a key with a different payload" contract; silently replaying would be wrong.
- Body hash matches → `replay_cached_response` sets the whitelisted headers, adds `Idempotent-Replayed: true`, and assigns `response_body`/`status` directly. The `return` means the block is never yielded, so the action's side effects don't happen twice.

**5. Cache miss (`:46-52`)** — runs the action, then caches the response if the status is 2xx/3xx/4xx. 5xx is deliberately *not* cached, so a server error remains retryable.

## The subtle part: the manual `rescue`

The comment at `:41-45` explains a real Rails ordering problem. `rescue_from` handlers fire in `process_action`, which is *outside* the `around_action` callback chain. So if the action raises, the exception unwinds past `yield` and the `write_idempotency_entry` line at `:52` never executes — meaning a 422 rendered by a `rescue_from` handler would never be cached, breaking the replay contract for client errors.

The fix is to dispatch the handler inline: `rescue_with_handler(error)` looks up and invokes the controller's registered handler (which renders the error response, populating `response.status`), and `raise unless` re-raises anything unhandled so genuine 500s still propagate normally. By the time control reaches `:52`, `response.status` reflects the rendered error.

## Safety valves

- **Fail-open cache** (`:59-64`, `:85-87`) — read and write errors are logged and swallowed. A Solid Cache hiccup degrades to ordinary non-idempotent processing rather than 500-ing the request.
- **Streaming guard** (`:69-72`) — an `Enumerator` body or `Transfer-Encoding: chunked` is skipped, since consuming the enumerator to cache it would break the response.
- **Header whitelist** (`:7-14`) — only content type, `Location`, and rate-limit headers are replayed. Notably keeps `Set-Cookie`/`ETag` out of the cache.
- **24h TTL** (`:5`).

## Two things worth knowing

**No concurrency lock.** Two simultaneous requests with the same key both miss the cache at `:27` and both execute the action. Stripe handles this by writing an "in progress" marker on miss and returning 409 to the second caller. As written, this concern protects against *sequential* retries (the common case: client timeout, then retry), not against a double-submit racing itself.

**`rescue_with_handler`'s return value is load-bearing.** Line `:49` re-raises when it returns falsy. It returns the handler's own return value, so a `rescue_from` handler whose last expression evaluates to `nil` or `false` would get its exception re-raised even though it rendered successfully. Handlers ending in `render` are fine; it's a trap for anything ending in, say, `head :no_content if ...`.

Also, `created_at` is written into the entry at `:81` but nothing reads it — dead weight unless something external inspects cache entries.
