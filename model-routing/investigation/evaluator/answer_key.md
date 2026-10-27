# Hidden answer key

Do not place this file in the model workspace or include it in model input.

## Diagnosis

`Checkout#charge` performs `find_by_order`, then calls the external gateway, then inserts. `PaymentStore` serializes each individual operation but does not serialize the whole workflow. Two requests may both find no row, both call the gateway, and then both insert rows. The repeated provider idempotency key is not enough to claim safety: the fake gateway intentionally makes no undocumented promise about deduplicating keys.

The deterministic test seam forces the interleaving: both threads complete lookup and block before either gateway call. Releasing both produces two gateway calls and two payment rows for one order.

## Qualifying correction

At minimum, make the local claim of one payment per order atomic with a database uniqueness constraint on the stable business key (for example `payments.order_id`) and handle the unique-conflict path by loading and returning the winner. A check-then-insert protected only by a Ruby mutex is not sufficient across processes/hosts. The service must not hold a database transaction open around a network request as its primary concurrency solution: that harms availability and still cannot make a remote side effect and a local commit one atomic transaction.

For robust production behavior, persist a durable payment attempt/outbox or equivalent state with a stable idempotency key and enforce uniqueness locally; dispatch/retry the provider call using that same key, then persist the result. This addresses crashes/timeouts between provider acceptance and local persistence. Whether the provider deduplicates that key must be confirmed from its documented contract. Without provider-side idempotency or a reconciliation/query mechanism, exactly-once charging cannot be guaranteed across an ambiguous network failure.

An alternative concise answer can describe serializing a per-order workflow with a durable lock/lease and a unique constraint, as long as it covers multi-process deployment, crash recovery, and external side-effect ambiguity. Merely wrapping the existing find, network call, and insert in a Ruby `Mutex` or a database transaction is insufficient.

## Expected regression evidence

A sound focused regression test runs two calls for the same order concurrently and asserts one durable local payment and at most one effective provider charge under the explicitly stated provider contract or durable-attempt design. It should also test retry after a simulated timeout after provider acceptance, demonstrating reuse of the same stable key and recovery/reconciliation rather than a new logical charge. The included fixture test proves the vulnerable interleaving; it is not itself a test of a proposed fix.
