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

**Runs.** 3 per condition. Two agents, fifteen conditions, 45 runs.

## Reading the numbers

The headline column is **startup context**: everything the model was sent before
it produced its first token.

For Claude that is `input_tokens + cache_creation_input_tokens +
cache_read_input_tokens` on the first assistant turn. The three are added rather
than chosen between, because they are three billing buckets for one prompt and
which bucket a token lands in depends on whether an earlier run warmed the
cache. The sum does not move. The price does, which is why cost appears in its
own table and is never compared across conditions.

For Codex the same quantity arrives by a different route: it reports usage once
per turn, and this probe is one turn with no tool calls, so the turn's
`input_tokens` is the startup context.

## Caveats

- **One machine, one week.** These numbers describe one developer's setup on
  2026-08-18, not Claude Code or Codex in general. What transfers is the method
  and the shape of the answer, not the totals.
- **The model is pinned** to `sonnet` for Claude and `gpt-5.6-sol` for Codex in
  every condition except `claude/host-default-model`, which exists to record
  what the machine actually reaches for when nobody pins anything. A condition
  that changed the model would move the system prompt underneath the layer being
  measured.
- **The container runs a slightly older CLI** than the host (see the versions in
  `results/tables.md`), because the base image pins its versions in
  `Kit::PINS`. The gap is one patch release and it is visible in the floor.
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
ruby containers/scripts/auth_setup.rb                  # once, interactive

export LLMX_PROJECT_DIR=/path/to/a/real/project        # for the host-project rows
ruby startup-context/scripts/probe.rb --all --repeats 3
ruby startup-context/scripts/inventory.rb
ruby startup-context/scripts/parse_probe.rb
ruby startup-context/scripts/report.rb --write
ruby startup-context/scripts/sanitize.rb
```

`probe.rb --list` prints the conditions. `probe.rb --agent claude --condition
host-full` runs one of them.
