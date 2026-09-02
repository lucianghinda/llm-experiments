The MCP tools are not connected and the CLI fallback needs approval, so this explanation comes from the file itself.

## What it does

`Idempotency` is a controller concern that makes API write requests safe to retry. A client sends an `Idempotency-Key` header; if the same key comes back later, the server replays the first response instead of doing the work a second time. This is the Stripe-style contract.

## Flow, step by step

**1. Gate (line 23).** The `around_action` does nothing unless all three conditions are true: the header is present, the method is `POST`/`PATCH`/`PUT`, and `Current.api_token` is set. `GET`s, browser traffic, and unauthenticated calls pass straight through.

**2. Cache key (line 56).** The key is scoped to the account, the controller, the action, the path, and the client key:

```
idem:<account_id>:<controller>#<action>:<path>:<key>
```

Account scoping prevents one tenant from touching another tenant's entries. Action and path scoping stop the same key from replaying across different endpoints.

**3. Request fingerprint (line 26).** A SHA256 of the raw request body. This detects key reuse with different content.

**4a. Cache hit (lines 29–39).**
- Different `body_hash` → raise `Api::Error::Conflict` (HTTP 409). The client reused a key for a different payload, which is a bug on their side.
- Same `body_hash` → `replay_cached_response` writes the stored status, body, and allow-listed headers into the current response, plus `Idempotent-Replayed: true` so the client knows it is a replay. The action never runs.

**4b. Cache miss (lines 46–52).** The action runs, then the response is cached.

## The interesting part: the `rescue` block

This is the subtle piece, and the comment at lines 41–45 explains why it exists.

`rescue_from` handlers are registered on the controller and run *outside* an `around_action`. So if the action raises — say a validation error that maps to a 422 — the exception unwinds past line 47, the `around_action` never reaches line 52, and nothing gets cached. The client retries and gets fresh work each time, which breaks the replay contract for 4xx responses.

The fix is to dispatch the handler manually:

```ruby
rescue StandardError => error
  raise unless rescue_with_handler(error)
end
```

`rescue_with_handler` runs the registered `rescue_from` handler and returns truthy if one matched. If a handler matched, it already rendered the error response, so control continues to line 52 and the entry is cached. If no handler matched, `raise` re-throws and the request fails normally, with nothing cached.

## What is cached, and what is not

Line 52 caches only statuses `200`–`499`. The reasoning:

- **2xx/3xx** — success, replay it.
- **4xx** — a deterministic client error. Retrying gives the same result, so replay it.
- **5xx** — a server fault, possibly transient. It is deliberately *not* cached, so a retry gets a real second attempt.

Two more guards in `write_idempotency_entry`:

- **Streaming responses (line 69)** are skipped. An `Enumerator` body or `Transfer-Encoding: chunked` cannot be captured as a string, and reading it would consume the stream.
- **Header allow-list (line 79)** — only `Content-Type`, `Location`, and the rate-limit headers are stored. This avoids replaying stale `Set-Cookie`, `ETag`, or request-specific headers.

Entries expire after 24 hours (`TTL`).

## Failure behavior

Both cache read and cache write wrap in `rescue StandardError`, log a warning, and continue. If the cache is down, the API keeps working — it just loses the idempotency guarantee instead of returning 500s. This is the correct trade-off: idempotency is an optimization on top of the request, not a precondition for it.

## One thing to be aware of

There is no in-flight lock. Two identical requests that arrive at the same time both miss the cache and both execute the action. The entry is written only *after* the action finishes. This protects against sequential retries, which is the common case, but not against concurrent duplicates. Handling that needs a reservation record written before the yield, usually with a "request in progress" state that returns 409.
