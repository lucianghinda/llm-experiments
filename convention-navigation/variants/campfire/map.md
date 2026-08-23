# Working in this codebase

This is a Rails application that does not use the default `app/` layout. Code is
organised by deployment concern: `platform/` is everything that runs regardless
of how a request arrived, `delivery/` is everything tied to a transport.

## Where things live

| What | Where |
|---|---|
| Models | `platform/core/entities/` |
| Model concerns | `platform/core/entities/concerns/` |
| Controllers | `delivery/http/handlers/` |
| Controller concerns | `delivery/http/handlers/concerns/` |
| Views and layouts | `delivery/http/render/` |
| Helpers | `delivery/http/render_support/` |
| Background jobs | `platform/async/workers/` |
| Action Cable channels | `delivery/sockets/` |
| Migrations | `db/changes/` |
| Routes | `config/routing/`, loaded by `config/routes.rb` |
| Tests | `test/suite/` |
| Non-domain support code | `lib/` |
| Stylesheets, images, JS | `app/assets/`, `app/javascript/` |

Rails is told about the moved trees in `config/application.rb`. A new top-level
directory of Ruby code is not autoloaded until it is registered there.

## Views

View lookup still follows the controller's name, as Rails does by default: the
templates for `RoomsController` are in `delivery/http/render/rooms/`. Only the
root directory has moved.

## Routes

`config/routes.rb` is a loader, not a route table. It evaluates the files in
`config/routing/` in a fixed order, which is significant because routes match in
the order they are drawn. The parts are named for the area they cover rather
than for a controller:

| File | Covers |
|---|---|
| `entry.rb` | root, first run, sessions |
| `accounts.rb` | accounts, bots, join codes, logos, custom styles |
| `people.rb` | users, joining, avatars, bans, profiles, push subscriptions |
| `spaces.rb` | rooms and everything nested under a room |
| `posts.rb` | top-level messages and boosts |
| `support.rb` | search, link unfurling, PWA endpoints, health check |

## Tests

`test/suite/` is grouped by kind, not mirrored onto the source tree:

| Directory | Holds |
|---|---|
| `test/suite/persistence/` | model tests |
| `test/suite/endpoints/` | controller tests |
| `test/suite/rendering/` | helper tests |
| `test/suite/realtime/` | channel tests |
| `test/suite/support/` | tests for `lib/` |
| `test/suite/browser/` | system tests |
| `test/suite/timing/` | performance scripts |

`test/test_helper.rb`, `test/test_helpers/` and `test/fixtures/` stay at the top
of `test/`. Run the suite with `bin/rails test`.
