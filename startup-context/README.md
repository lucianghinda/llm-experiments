# What does an agent load before it starts work?

**Question.** A coding agent arrives at a task carrying a system prompt, tool
schemas, a catalogue of whatever the machine has installed, and any memory files
it found on the way. How big is that, where does it come from, and which parts
can be turned off?

**Method.** Ask for something no configuration can help with, then measure what
arrived anyway.

```
Reply with exactly: OK
```

The answer is in the prompt. A run that reads a file or calls an MCP server has
failed the check, not passed it, so everything counted is overhead. The same
prompt runs unchanged in every condition, and each condition removes exactly one
layer, so the difference between two rows is the price of the layer between
them.

The floor is a fresh Apple container from [`containers/`](../containers/): a
freshly installed CLI, no user memory file, no MCP servers, no hooks, no
plugins, no project. Everything above it is what this machine adds.

**Runs.** 3 per condition, and 7 for each of the four opencode rows that take
the config directory apart, because the first reading of those came out
backwards and the extra runs are what showed why. Three agents, 25 conditions,
91 runs.

Codex and opencode are both pinned to `gpt-5.6-sol`, so they are the one pair
here that can be compared directly: what differs between them is the harness and
not the model.

## Reading the numbers

The headline column is **startup context**: everything the model was sent before
it produced its first token.

For Claude that is `input_tokens + cache_creation_input_tokens +
cache_read_input_tokens` on the first assistant turn. The three are added rather
than chosen between, because they are three billing buckets for one prompt and
which bucket a token lands in depends on whether an earlier run warmed the
cache. The sum does not move. The price does, which is why cost appears in its
own table and is never compared across conditions.

For Codex and opencode the same quantity arrives by a different route. Codex
reports usage once per turn and opencode once per step, and this probe is a
single turn with a single step and no tool calls, so each one's input count is
the startup context.

The three CLIs do not agree on what "input" means, and getting this wrong is the
easiest way to publish a wrong number:

| CLI | Field | Cached tokens |
|---|---|---|
| Claude Code | `input_tokens` | reported separately in `cache_read_input_tokens` and `cache_creation_input_tokens`; all three are added |
| Codex | `input_tokens` | **included**; `cached_input_tokens` is a subset, reported for information |
| opencode | `tokens.input` | **excluded**; `tokens.cache.read` has to be added back |

The opencode row cost a wrong result before it was noticed. Reading `input`
alone split every opencode condition into two clusters about 35% apart, which
looked like the CLI loading different things on different runs. Three host-full
runs reported 33,935 with no cache, then 22,130 and 22,321 each with exactly
11,776 cache reads. `parse_probe.rb` now warns when repeats of one condition
disagree by more than 10%, because that is what this looked like from the
outside.

## Caveats

- **One machine, one week.** These numbers describe one developer's setup on
  2026-08-18, not Claude Code, Codex or opencode in general. What transfers is
  the method and the shape of the answer, not the totals.
- **The model is pinned** to `sonnet` for Claude and `gpt-5.6-sol` for Codex and
  opencode, in every condition except `claude/host-default-model`, which exists
  to record what the machine actually reaches for when nobody pins anything. A
  condition that changed the model would move the system prompt underneath the
  layer being measured.
- **The container runs a slightly older CLI** than the host (see the versions in
  `results/tables.md`), because the base image pins its versions in
  `Kit::PINS`. The gap is one patch release and it is visible in the floor.
- **opencode's floor comes from a different image.** The base image does not
  carry opencode, so `containers/opencode/` adds it in one layer on top. The
  opencode floor is therefore the same environment as the other two plus one npm
  package, not a byte-identical one.
- **opencode has no ephemeral mode.** Claude gets `--no-session-persistence` and
  Codex gets `--ephemeral`; opencode writes every run into `XDG_DATA_HOME`, which
  is also where it keeps its credentials. Every opencode condition therefore
  points that variable at a fresh directory holding the credential file alone.
  That was checked rather than assumed: against the real data directory the same
  prompt measured 34,011 tokens and against a private one 33,917, a gap smaller
  than opencode's own run-to-run spread.
- **opencode's container credentials are copied, not re-logged-in.**
  `auth_setup.rb` opens a container and runs the real login flow for Claude and
  Codex. opencode keeps credentials in the same directory as its sessions and its
  database, so that shape does not fit yet, and
  `containers/scripts/seed_opencode_auth.rb` copies the one credential file into
  the kit's store instead. The file never enters an image and never leaves the
  machine.
- **`--disallowed-tools Task` is a proxy**, not a switch. There is no flag that
  turns subagents off. The catalogue of available subagents ships inside the
  Task tool's own description, so disallowing the tool removes both, and the
  measured saving is the catalogue plus one tool schema.
- **Codex has no `init` event.** Claude announces everything it attached; Codex
  announces nothing. Its loaded surface had to be read off disk by
  `scripts/inventory.rb` instead, which is why the per-layer table is shorter
  for Codex.
- **The published transcripts carry counts, not names.** `results/` is produced
  by `sanitize.rb`, which replaces every list of installed items with its own
  length: how many skills, subagents, plugins, slash commands and MCP servers,
  and for the servers how many were connected, failed or needed auth. The text
  the session hooks injected is replaced by its byte count for the same reason,
  since it is the body of an installed skill. Nothing measurable is lost, because
  every claim in RESULTS.md is a difference between two token totals. Reproducing
  the names means running the probe on your own machine, where `results-raw/`
  keeps everything.
- **Published paths are placeholders.** `<home>`, `<repo>`, `<project>` and
  `<tmp>` stand in for the four real locations, in both the literal spelling and
  the slug spelling Claude uses for its state directories. The shape survives,
  so a reader can still see that Claude derives a per-project memory directory
  from the working directory, and the machine's layout does not.

- **One condition cannot remove only one layer, and it is worth knowing which.**
  opencode has no flag that suppresses its MCP servers, so `host-no-mcp` builds
  a config directory instead of passing an argument, which moves
  `XDG_CONFIG_HOME` at the same time. That move turned out to cost 2,388 tokens
  on its own, which is more than the layer it was trying to measure. The three
  `host-config-*` rows exist to separate the two, and the general lesson is that
  a condition built by relocating something has changed the location as well as
  the contents. For opencode the location is itself a measurable layer; see
  RESULTS.md.

- **The probe measures the first request only.** Everything counted here is
  also carried by every later request in the session, so it is a floor, not a
  one-off charge.

## Layout

```
startup-context/
  PROMPTS.md                the prompt, unedited
  prompts/probe.txt         the prompt as the scripts read it
  scripts/conditions.rb     the condition list, shared by probe.rb and report.rb
  scripts/probe.rb          runs one condition, host or container, and records raw output
  scripts/parse_probe.rb    raw JSONL -> per-run metrics.json + summary.json
  scripts/inventory.rb      what is installed on this machine, read off disk
  scripts/report.rb         summary.json + inventory.json -> the tables in RESULTS.md
  scripts/sanitize.rb       the gate between results-raw/ and results/
  results-raw/              every run as produced (gitignored: host paths and names)
  results/                  what crosses into the repository: counts, not names
  RESULTS.md                the numbers and what they mean
```

## Running it

```sh
ruby containers/scripts/build_base.rb                  # once
ruby containers/scripts/build_opencode_image.rb        # once, adds opencode on top
ruby containers/scripts/auth_setup.rb                  # once, interactive
ruby containers/scripts/seed_opencode_auth.rb          # once, copies opencode's credential file

export LLMX_PROJECT_DIR=/path/to/a/real/project        # for the host-project rows
ruby startup-context/scripts/probe.rb --all --repeats 3
ruby startup-context/scripts/inventory.rb
ruby startup-context/scripts/parse_probe.rb
ruby startup-context/scripts/report.rb --write
ruby startup-context/scripts/sanitize.rb
```

`probe.rb --list` prints the conditions. `probe.rb --agent claude --condition
host-full` runs one of them.

## What each agent lets you turn off

The three CLIs expose very different amounts of control, and that shows up in
how many conditions each one has.

| | Claude Code | Codex | opencode |
|---|---|---|---|
| Says what it loaded | `init` event, item by item | nothing | nothing |
| Warns when it truncates | no | yes | no |
| MCP off for one run | `--strict-mcp-config` | `-c mcp_servers={}` | config file only |
| Skills off for one run | `--disable-slash-commands` | no | config file only |
| Subagents off for one run | only by refusing `Task` | no | no |
| Everything off for one run | `--safe-mode` | no | `--pure` is partial |
| Session not written | `--no-session-persistence` | `--ephemeral` | no |

