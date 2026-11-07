# Manual check: `@AGENTS.md` import order

Day 1 finding 2 says: with `@AGENTS.md` at the top of CLAUDE.md, the docs say Claude reads the
imported file first, but the lab saw the CLAUDE.md marker first. That came from what the model
reported. This page checks the real layout in two ways.

What the docs claim, verbatim ([memory#agents-md](https://code.claude.com/docs/en/memory#agents-md)):

> Add any Claude-specific instructions below the import, and Claude reads the imported file first, then the rest

## 1. Build the sandbox

```sh
bin/lab --only claude-imports-agents --build-only --keep
```

It prints the sandbox path and a run id. The files are:

- `CLAUDE.md`: `@AGENTS.md`, blank line, `Marker CANARY_C_ROOT_<id>`
- `AGENTS.md`: `Marker CANARY_A_ROOT_<id>`

## 2. Capture the real request (exact, no model call)

```sh
bin/capture-prompt <sandbox path>
```

This is the Claude side of `codex debug prompt-input`. It starts a local HTTP server, points
`ANTHROPIC_BASE_URL` at it, runs `claude -p hi` in the sandbox, saves every request body to
`results/captures/`, and prints the order of every `CANARY_` token and every `Contents of ...`
memory block. It replies 400 so no model is called and nothing is billed.

It passes the same `--settings` the lab uses (Project instructions = `claude-md-or-agents-md`),
so your own `/config` choice does not change the result. Extra Claude flags go after `--`.

`results/captures/` holds the full request, including your global `~/.claude/CLAUDE.md` and the
MCP tool list. It is gitignored for that reason. The repo is public.

What to look for:

- Are the two markers in one block or two?
- Is the `@AGENTS.md` line still literally there, or replaced by the AGENTS.md text?
- Which block comes first?

## 3. Interactive session with `/context`

Launch with the same settings the lab uses:

```sh
cd <sandbox path>
claude --settings '{"pluginConfigs":{"cc-plugin-agents-md@builtin":{"options":{"instructionFiles":"claude-md-or-agents-md"}}}}'
```

Then run `/context all` and read the **Memory files** list. The docs say this list confirms a
file loaded. Check whether it also shows an order, or just the file list and sizes. Either way
step 2 is the order proof. Use both when writing it up.

Also try `/memory` and note whether it shows AGENTS.md as loaded through the import.

## Result on 2026-11-07 (Claude Code 2.1.318)

Capture from `bin/capture-prompt`, first request with markers:

```
CANARY tokens in request order:
    14373  CANARY_C_ROOT_170c
    14589  CANARY_A_ROOT_170c

Memory blocks, in order:
  Contents of ~/.claude/CLAUDE.md (user's private global instructions for all projects):
  Contents of <sandbox>/CLAUDE.md (project instructions, checked into the codebase):
  Contents of <sandbox>/AGENTS.md (project instructions, checked into the codebase):
```

The CLAUDE.md block keeps the literal `@AGENTS.md` line. AGENTS.md is a separate block, appended
after it. So the model's report in the lab matched the real layout: the parent file comes first,
the imported file after. The docs sentence above does not match Claude Code 2.1.318.

Memory files are not in the API `system` field. They travel in a `<system-reminder>` inside the
first user message. `bin/capture-prompt` scans both.

### Controls, same day, same version

Two more captures rule out the other explanation, that the AGENTS.md plugin loaded the file on
its own rather than the import:

- `claude-and-agents` (CLAUDE.md and AGENTS.md, no import): blocks are global CLAUDE.md, then
  project CLAUDE.md. No AGENTS.md block at all. So in the main capture the AGENTS.md block can
  only come from the `@AGENTS.md` import.
- `import-inside-agents` (AGENTS.md with `@docs/style.md` at the bottom): blocks are global
  CLAUDE.md, AGENTS.md, then `docs/style.md`. Same pattern: the imported file is its own block,
  appended after the parent, labelled "project instructions, checked into the codebase".

So this is how every `@import` works, not something special about `@AGENTS.md`. Expanded
imports go after the parent file. "Claude reads the imported file first" is not what the prompt
shows.

### Interactive `/context all`, same day, same version

```
Memory files · /memory
├ ~/.claude/CLAUDE.md: 487 tokens
├ CLAUDE.md: 34 tokens
└ AGENTS.md: 25 tokens
```

Three rows, one per file, in the same order as the captured request. AGENTS.md is its own row
with its own token count, so it is not spliced into CLAUDE.md. The 34 tokens for CLAUDE.md cover
the literal `@AGENTS.md` line plus the marker. The view lists files from the same loader that
builds the prompt, with no sorting, so this order is the prompt order.

All three checks agree: model report, captured request, and `/context all`.
