`Idempotency` is a controller concern implementing Stripe-style idempotent writes via an `around_action`.

**Gate (line 23)** — it only engages when all three hold: an `Idempotency-Key` header is present, the method is POST/PATCH/PUT, and there's an authenticated `Current.api_token`. Otherwise it just yields.

**Cache key (line 56)** — `idem:<account_id>:<controller#action>:<path>:<key>`. Scoping by account means one tenant's key can't collide with another's; scoping by endpoint means the same key reused on a different action is treated as a fresh request.

**Replay path (lines 29-39)** — on a hit, it SHA-256s the raw request body and compares to the stored `body_hash`. Mismatch → `Api::Error::Conflict` ("same key, different body"), which is the standard guard against a client accidentally reusing a key. Match → `replay_cached_response` restores the stored status, body, and the whitelisted headers (`CACHED_HEADERS`: content type, `Location`, rate-limit headers), plus adds `Idempotent-Replayed: true` so callers can tell a replay from a real execution.

**Miss path (lines 46-52)** — the interesting part, explained in the comment: `rescue_from` handlers registered on the controller run *outside* an `around_action`, so if the action raises, the code after `yield` never runs and nothing gets cached. To still cache error responses, the concern catches `StandardError` itself and calls `rescue_with_handler(error)` — that dispatches the controller's own `rescue_from` handler inline (rendering e.g. a 422), so control returns here normally. If no handler matches, `rescue_with_handler` returns falsy and it re-raises.

**Write policy (line 52)** — caches when status is 200-499, for 24h. So 2xx *and* 4xx responses are stored and will replay; 5xx are deliberately not cached, letting a client retry after a server failure. `write_idempotency_entry` bails on streaming/chunked responses (`response.body` would be an Enumerator you can't safely store), and both read and write swallow cache errors with a log warning — a Rails.cache outage degrades to non-idempotent behavior rather than failing the request.

Two behavioral caveats worth knowing: there's no lock or in-flight marker, so two concurrent requests with the same key both execute the action (the entry is only written after the first finishes). And `response.body` is cached as a raw string, so replays skip any per-request re-rendering.
