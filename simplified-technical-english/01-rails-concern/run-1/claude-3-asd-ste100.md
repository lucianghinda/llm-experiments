# The Idempotency module

## 1. Purpose

The Idempotency module is a Rails concern. A controller includes this module.

The module makes sure that a client can send the same write request more than one time. The server does the work one time only. For each subsequent request, the server sends a copy of the first response.

## 2. The constants

The module has five constants:

- WRITABLE_METHODS contains the three HTTP methods POST, PATCH and PUT.
- TTL is 24 hours. TTL is the time that the server keeps a stored response.
- HEADER is the name of the HTTP header `Idempotency-Key`.
- CACHED_HEADERS is a list of six response headers. The module keeps only these headers.

The list CACHED_HEADERS contains `Content-Type`, `Location` and the four rate limit headers.

## 3. When the module operates

The module adds an `around_action` callback with the name `wrap_in_idempotency`. Rails runs this callback around each controller action.

First, the callback reads the header `Idempotency-Key` from the request. Then the callback makes a test with three conditions:

1. The header has a value.
2. The HTTP method is POST, PATCH or PUT.
3. `Current.api_token` has a value. This shows that the client has authentication.

If one condition is not true, the callback runs the action and stops. The module does no other operation. Thus GET requests and requests without a key stay unchanged.

## 4. The cache key and the hash value

The callback makes a cache key. The key is a text string with five parts:

1. the text `idem`
2. the account ID of the API token
3. the controller path and the action name
4. the path of the request
5. the value of the header `Idempotency-Key`

Two different accounts can use the same key value. The account ID keeps the two entries separate. The controller path, the action name and the request path do the same for two different endpoints.

The callback also calculates a SHA256 hash value of the raw request body. This value identifies the content of the body.

Then the callback reads the cache with the cache key. The subsequent operation depends on the result of this read operation.

## 5. Flow A: the cache has no entry

If the cache has no entry, the request is new. The callback does these steps:

1. The callback runs the controller action.
2. The action makes a response.
3. The callback examines the status of the response.
4. If the status is 200 to 499, the callback writes an entry in the cache.
5. The entry stays in the cache for 24 hours.

The entry contains five items: the status, the body, the headers from the list CACHED_HEADERS, the hash value of the request body, and the time.

The module does not keep server errors. A status of 500 or more is a server error. Thus the client can send the same request again after a failure of the server.

## 6. Flow B: the cache has an entry with the same body

If the cache has an entry, the callback compares the two hash values. If the two values are the same, the callback sends the stored response again. The callback does these steps:

1. It sets the stored headers on the response.
2. It sets the header `Idempotent-Replayed` to `true`.
3. It sets the stored body.
4. It sets the stored status.

The callback does not run the controller action. Thus the server does not do the work a second time. The client sees the header `Idempotent-Replayed`. This header tells the client that the response is a copy.

## 7. Flow C: the cache has an entry with a different body

If the two hash values are different, the client used one key for two different requests. This is an error.

The callback raises the error `Api::Error::Conflict`. The client receives the HTTP status 409. The message gives the cause of the error. The details contain the key.

This test prevents a dangerous condition. A client cannot use one key to get the response of a different operation.

## 8. Errors in the controller action

Rails keeps the `rescue_from` handlers at the controller level. These handlers operate outside of the `around_action` callback. If the action raises an error, Rails goes directly to a handler. Thus the code after the `yield` does not run.

The module prevents this condition. The callback puts the `yield` in a `begin`/`rescue` block:

- If the action raises an error, the callback calls `rescue_with_handler`. This method finds the correct handler and runs it. The handler makes the error response.
- If a handler is available, `rescue_with_handler` gives a true value. Then the callback continues and examines the status of the response. Thus the module can also keep 4xx responses.
- If no handler is available, the callback raises the error again.

This behavior agrees with the contract of Stripe. The server sends the same 4xx response again for a repeated key.

## 9. Failures of the cache

A failure of the cache must not stop the request:

- If the read operation fails, the method `read_idempotency_entry` writes a warning in the log. The method gives a nil value. The request continues as a new request.
- If the write operation fails, the method `write_idempotency_entry` writes a warning in the log. The client receives the correct response.

The module does not keep a response that the server sends in parts. If the body is an `Enumerator`, or if the header `Transfer-Encoding` is `chunked`, the module writes a warning in the log and stops the write operation. The server can read such a body one time only. A copy of the body is not possible.

## 10. Summary of the rules

| Condition | Result |
| --- | --- |
| No key, or a read method, or no token | The module does nothing. |
| A new key | The server does the work. The module keeps the response for 24 hours. |
| The same key and the same body | The server sends the stored response again with the header `Idempotent-Replayed`. |
| The same key and a different body | The server sends the HTTP status 409. |
| A status of 500 or more | The module does not keep the response. The client can send the request again. |
| A failure of the cache | The module writes a warning in the log and continues. |
