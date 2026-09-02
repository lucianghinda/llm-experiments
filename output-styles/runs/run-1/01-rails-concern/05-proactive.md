Here's how `app/controllers/concerns/idempotency.rb` works.

## Purpose

It gives the API Stripe-style idempotency: a client sends an `Idempotency-Key` header with a write request, and if that same request is retried (network blip, timeout, client retry loop), the server replays the original response instead of performing the work twice.

## The gate (line 23)

The `around_action` wraps every action, but immediately `yield`s through unless **all three** hold:

- an `Idempotency-Key` header is present,
- the method is `POST`/`PATCH`/`PUT` (`WRITABLE_METHODS`) — `GET`/`DELETE` are untouched,
- `Current.api_token` is set, i.e. this is an authenticated API request.

So browser traffic and unauthenticated requests bypass the whole mechanism.

## Cache key and body fingerprint (lines 25–26)

```
idem:<account_id>:<controller_path>#<action>:<request.path>:<key>
```

The key is scoped per account, per action, and per path — so the same client-supplied key used against two different endpoints won't collide, and one tenant can't read another's cached response. Alongside it, a SHA-256 of the raw request body is computed as a fingerprint.

## Replay path (lines 29–39)

If an entry exists:

- **Body mismatch → 409.** If the stored `body_hash` differs from the current one, the client reused a key with different content, which is a client bug; it raises `Api::Error::Conflict` rather than silently returning the wrong answer.
- **Match → replay.** `replay_cached_response` restores the cached headers (only the `CACHED_HEADERS` allowlist: content type, `Location`, and the rate-limit headers), sets `Idempotent-Replayed: true` so the client can tell it was a replay, then sets `response_body` and `status` directly. Returning here means the action body never runs — no duplicate charge, no duplicate record.

## First-execution path (lines 41–52)

The interesting part is the comment. `rescue_from` handlers registered on the controller run *outside* an `around_action`, so if the action raises, the exception propagates past this filter and everything after `yield` is skipped — meaning error responses would never get cached. Since the contract is to replay 4xx responses too (a validation failure should stay a validation failure on retry, not be re-attempted), the concern calls `rescue_with_handler(error)` itself:

- if a handler exists, it runs and renders the error response, and control falls through to the cache write;
- if not, `raise` re-raises so the normal error path (500, error reporting) is unaffected.

Then line 52 writes the entry only for statuses **200–499**. 5xx is deliberately excluded — a server error is presumed transient, so a retry should actually re-run the action.

## Cache write (lines 66–87)

- Skips streaming responses (`Enumerator` body or `Transfer-Encoding: chunked`) — you can't buffer those into the cache without consuming them.
- Stores status, body, allowlisted headers, the body hash, and `created_at`, with a 24-hour TTL.

Both read and write are wrapped in `rescue StandardError` that logs a warning and continues. That's a deliberate fail-open: if the cache backend (SolidCache here) is down, requests still succeed — you lose idempotency guarantees rather than the endpoint.

## One thing worth knowing

There's no in-flight lock. Two truly concurrent requests with the same key can both miss the cache and both execute the action, since the entry is only written after the action completes. The typical hardening is to write a "processing" sentinel before `yield` and return `409` on a concurrent hit. Whether that matters depends on whether your clients retry aggressively before the first response lands.
