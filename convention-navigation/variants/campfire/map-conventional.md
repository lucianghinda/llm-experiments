# Working in this codebase

This is a Rails application using the default `app/` layout. Code is organised
the way Rails organises it: everything the framework autoloads sits under
`app/`, one directory per kind of thing.

## Where things live

| What | Where |
|---|---|
| Models | `app/models/` |
| Model concerns | `app/models/concerns/` |
| Controllers | `app/controllers/` |
| Controller concerns | `app/controllers/concerns/` |
| Views and layouts | `app/views/` |
| Helpers | `app/helpers/` |
| Background jobs | `app/jobs/` |
| Action Cable channels | `app/channels/` |
| Migrations | `db/migrate/` |
| Routes | `config/routes.rb` |
| Tests | `test/` |
| Non-domain support code | `lib/` |
| Stylesheets, images, JS | `app/assets/`, `app/javascript/` |

Rails autoloads every directory under `app/` without being told to, so a new one
is picked up as soon as it exists. `config/application.rb` does not list them.

## Views

View lookup follows the controller's name, as Rails does by default: the
templates for `RoomsController` are in `app/views/rooms/`.

## Routes

`config/routes.rb` is a single route table of about a hundred lines. It covers
the root and first run, sessions, accounts and bots, users and joining, rooms
and everything nested under a room, messages and boosts, and then search, link
unfurling and the PWA endpoints. Routes match in the order they are drawn, so
position in the file is significant.

## Tests

`test/` mirrors the source tree, one directory per kind:

| Directory | Holds |
|---|---|
| `test/models/` | model tests |
| `test/controllers/` | controller tests |
| `test/helpers/` | helper tests |
| `test/channels/` | channel tests |
| `test/lib/` | tests for `lib/` |
| `test/system/` | system tests |
| `test/performance/` | performance scripts |

`test/test_helper.rb`, `test/test_helpers/` and `test/fixtures/` stay at the top
of `test/`. Run the suite with `bin/rails test`.
