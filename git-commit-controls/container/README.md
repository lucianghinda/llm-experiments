# Running this experiment in a clean room

The first pass ran on the host. That left one caveat to remove: Claude Code
could not be isolated, because pointing `CLAUDE_CONFIG_DIR` at a sandbox broke
authentication, so the machine's own `~/.claude/CLAUDE.md` and `settings.json`
were a constant in every Claude arm rather than absent.

This directory is the second pass. Every trial runs in a fresh Apple container
with no agent configuration of any kind.

## What isolation buys here

| Host run | Clean room |
|---|---|
| `~/.claude/CLAUDE.md` present in every Claude arm | no such file exists |
| `~/.claude/settings.json` sets `attribution.sessionUrl: false` | no user settings at all |
| host `SessionStart` hooks suppressed with `disableAllHooks` | no hooks exist, so the setting is not needed |
| host git 2.47 builds the fixture | the container's own git 2.43 builds it |
| CLI resolved past a cmux wrapper shim | no shim exists |

The container arms therefore carry only the settings under test and
nothing else, which is why `disableAllHooks` is absent from every container arm.

## No image was built

`llmx-base` already ships all three CLIs, but pinned older than the versions
under test. Building a derived image was tried and abandoned: a BuildKit `RUN`
step uses `/bin/sh -c`, which does not pick up the mise shims on `PATH`, so
`npm` was not found, and the attempt cost about 8 GB of builder VM before it
failed.

The Containerfile is not kept here, because a build file that is known not to
work is worse than a paragraph explaining why. What replaced it costs nothing to
build: the pinned CLIs are installed into `~/.llmx/tools` from inside a plain
`container run`, then mounted read-only into every trial. That is the same shape `output-styles/` used, and it keeps the
machine's disk out of it. Versions used are recorded in every trial's
`meta.json`.

## Credentials, and the rotation trap

The kit's convention is that `~/.llmx/auth` is a **seed, not a home**: a trial
copies the credential files into a container-local directory and points the CLI
at the copy, so no run can share state with another.

That convention has a sharp edge this experiment hit. Anthropic rotates
refresh tokens. When the seed's access token has expired, the first trial
refreshes it successfully inside its own container, gets a new refresh token,
and then throws that container away. Every later trial replays the old refresh
token, which the rotation has just invalidated, and the whole sweep dies with:

```
Failed to authenticate: OAuth session expired and could not be refreshed
```

The failure looks like a broken login and is a discarded one. It only
appears when the seed is old enough to need a refresh, which is why a sweep can
work on the day of login and fail a week later.

`container_trial.rb` now copies `.credentials.json` back to the seed after a
Claude trial. Only that one file goes back. Settings, projects and sessions
stay container-local, so the behavioural clean room is unaffected.

## Running it

```sh
ruby containers/scripts/auth_setup.rb --agent claude   # when a refresh token dies
ruby containers/scripts/seed_opencode_auth.rb          # opencode, no login needed

export GCC_WORK=/tmp/gccc
ruby scripts/container_runner.rb claude 16 control
ruby scripts/container_runner.rb codex 2
ruby scripts/container_runner.rb opencode 2

GCC_RUNS=runs-container ruby scripts/measure.rb
GCC_RUNS=runs-container ruby scripts/report.rb
ruby scripts/compare.rb                                # host beside clean room
```

Trials run one container at a time at a 2 GB / 2 CPU envelope rather than the
kit's 6 GB default, because a commit message is a small thing to ask for. Each
trial directory is deleted once its message has been read.

## What the clean room caught

Re-running an experiment in isolation is only worth the trouble if it changes
something. It changed one thing, and the change is large.

**Codex's default commit style was a host artifact.** On the host, Codex wrote
Conventional Commits with an explanatory body in 8 of 8 control trials, against
deliberately plain history. In the clean room it wrote a plain one-line subject
in 8 of 8. Same Codex build (0.153.4), same `auth.json`, same prompt, same
fixture, same isolated `CODEX_HOME` holding no `config.toml`.

The difference is the environment. Codex inherits the host shell environment
by default, and re-running it *on the host* under `env -i` with only `HOME`,
`PATH` and `CODEX_HOME` set reproduced the clean-room result immediately:

```
scrubbed-env run 1: Fix cart total to account for item quantities
scrubbed-env run 2: Fix cart total to account for item quantities
```

So Codex's commit style is sensitive to inherited environment variables. A clean
room is the only way to see that, because every other input was already
controlled.

The knock-on is that Codex's instruction channels only become *measurable* once
the environment is clean. On the host, `AGENTS.md`, `developer_instructions` and
`model_instructions_file` all looked like no-ops, because the default already
produced what they asked for. In the clean room each moves Codex from 0/8 to
2/2.

**Claude Code's conclusions did not change.** The clean room's attribution rate
looked much lower at first (3/16 against the host's 8/16), but that gap is
mostly *CLI version*, not host configuration: the clean room's default build is
2.1.258 and the host ran 2.1.263. Running the same control arm on 2.1.263 inside
the container gives 6/16, which is not distinguishable from the host's 8/16.
`control-opus` reproduces the host exactly at 8/8.

**opencode's conclusions did not change** in any arm.
