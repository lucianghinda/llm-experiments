# Task catalog

Freeze these prompts before any treatment runs. The natural version is the
first-stage request for the natural-session track. The specified version is
complete and asks for implementation directly. Neither version mentions a
plugin or rewards a particular architecture. Keep hidden checks outside the
agent-visible checkout.

| ID | Fixture | Case | Follow-up |
|---|---|---|---|
| `report` | `fixtures/report` | Small behavior addition: filter a summary by status while preserving overall count and total behavior. | None |
| `identifiers` | `fixtures/identifiers` | Bug fix: normalize identifiers consistently across two existing callers. | None |
| `cancellation` | `fixtures/cancellation` | Existing service pattern: add cancellation through the established order result/service convention. | None |
| `csv_import` | `fixtures/csv_import` | External boundary: import CSV atomically while validating rows. | Add a second CSV header format; prompt in `prompts/csv_import/followup.txt`. |
| `campfire_feature` | `fixtures/campfire_feature` | Rails feature across persistence, controller, and view layers, preserving room authorization. | Verify that a room creator who is not an account administrator can edit the topic while another member cannot; prompt in `prompts/campfire_feature/followup.txt`. |
| `campfire_safety` | `fixtures/campfire_safety` | Safety-sensitive credential-scope bug: bot credentials must not authenticate as non-bots. | None |

## Ruby fixture contracts

- `OrderReport.new(orders).summary(status: nil)` returns `{ count:, total: }`;
  nil status includes all orders. A supplied status filters both values.
- `Identifiers.normalize(value)` strips and lowercases strings and returns nil
  for blank input. `Importer#import(values)` and
  `ManualEntry#create(value)` share that normalization and reject blank values
  with `ArgumentError`.
- `Orders::Cancel.call(order)` returns the same result shape as
  `Orders::Ship.call(order)`: `success?` and `error`. Pending orders become
  cancelled; shipped and already-cancelled orders fail without mutation.
- `Contacts::Importer#import(csv)` accepts `name,email` headers, returns the
  imported count, and raises `ArgumentError` for a blank name or an email
  without `@`. Malformed CSV syntax raises `CSV::MalformedCSVError`. Either
  kind of failure leaves storage unchanged.

### CSV reviewer note

Keep parser syntax failures distinct from row validation failures in prompt
reviews and hidden checks: `CSV::MalformedCSVError` is the expected parser
exception, while invalid contact fields raise `ArgumentError`.

## Campfire ground truth

Source checkout: `/Users/luciang/Dropbox/workprojects/opensource/once-campfire`,
HEAD `f1aec6133667a7486d521430f871bc420e18ec2b`, observed clean at catalog time.
The room topic feature starts from a snapshot with no topic column. Existing
open and closed room update actions use `ensure_can_administer`; the current
policy permits account administrators and the room creator, and their room
scope excludes direct rooms. The bot-auth defect is the planted `bot-auth-scope`
case from `llm-experiments/at-file-mentions`: `app/models/user/bot.rb`, with
regression coverage in `test/controllers/messages/by_bots_controller_test.rb`.
The defect allows a key intended for an automated account to match a regular
enabled account. Do not expose the fix SHA, planted patch, or hidden test to
subjects.

The two follow-ups use a fresh session with the first-stage patch applied and
the assigned plugin retained. Record first-stage failures; do not drop those
runs from the denominator. The Campfire task entries in `tasks.json` remain
blocked until their baseline suite and hidden checks run in an isolated Rails
checker. The snapshot preparation test proves provenance and the planted code
change only; it does not prove that the Rails fixture boots or the hidden checks
pass after a fix.
