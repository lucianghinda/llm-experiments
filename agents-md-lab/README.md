# agents-md-lab

A small lab for Day 1 of Re-learning Claude Code and Codex. It checks which instruction files Claude Code and Codex really load, instead of trusting the docs or my memory.

## How it works

Each scenario builds a tiny git repo in a temp folder. Every instruction file holds one marker, like `CANARY_A_ROOT_3f9a`. The suffix changes on every run, so nothing remembered from an earlier run can match.

- **Codex**: `codex debug prompt-input hello` prints exactly what Codex sends to the model. The lab looks for the markers in that output. No model call, so it is free and exact.
- **Claude Code**: there is no equivalent, so the lab asks `claude -p` to list the markers it has in context. It records every tool Claude used, and marks the result `SUSPECT` if Claude opened an instruction file itself.

Each scenario lists what the docs say should happen, and the lab compares that with what it gets.

## Run it

Ruby 3 and the standard library only.

```sh
bin/lab                          # every scenario, both tools
bin/lab --tool codex             # only Codex, free and fast
bin/lab --tool claude            # only Claude, about 16 short haiku calls
bin/lab --only override-file     # one scenario, or a comma separated list
bin/lab --model sonnet           # another Claude model
bin/lab --build-only --keep      # just build the repos so you can poke at them by hand
bin/capture-prompt <dir>         # dump the exact request Claude sends from <dir>, no model call
```

Each run writes a Markdown report to `results/`.

## Results

| Result | Meaning |
|---|---|
| PASS | Got exactly the expected markers, in the expected order |
| ORDER | Right markers, different order |
| FAIL | A marker is missing or extra |
| SUSPECT | Claude opened an instruction file on its own, so the result does not count |
| ERROR | The tool did not run (not installed, timed out) |

## Scenarios

| Scenario | What it checks |
|---|---|
| agents-only | Only AGENTS.md exists |
| claude-and-agents | CLAUDE.md wins over AGENTS.md in Claude; Codex ignores CLAUDE.md |
| claude-imports-agents | CLAUDE.md with `@AGENTS.md` |
| local-turns-agents-off | A CLAUDE.local.md switches AGENTS.md off in Claude |
| local-with-and-setting | Same, with Project instructions set to `claude-md-and-agents-md` |
| nested-launch-in-subfolder | Root and `app/` files when launched in `app/` |
| dot-claude-agents | `.claude/AGENTS.md` |
| override-file | `AGENTS.override.md` |
| agents-local-and-dot-agents | `AGENTS.local.md` and `.agents/` |
| import-inside-agents | `@path` inside AGENTS.md |
| subfolder-on-read | A subfolder AGENTS.md after the Read tool |
| subfolder-on-cat | A subfolder AGENTS.md after `cat` |
| subfolder-claude-on-cat | Control: a subfolder CLAUDE.md after `cat` |
| subfolder-with-own-claude | A subfolder with both CLAUDE.md and AGENTS.md |
| codex-fallback-name | `project_doc_fallback_filenames` with TEAM_GUIDE.md |
| codex-fallback-claude-md | Untested Day 1 idea: CLAUDE.md as a Codex fallback name |
| codex-size-budget | The 32 KiB `project_doc_max_bytes` budget across two files |

To add a scenario, add a hash to `lib/scenarios.rb`.

## Things to know

- The lab passes `--settings` with an explicit Project instructions value on every Claude run, so your own `/config` choice does not change the result.
- Your `~/.claude/CLAUDE.md`, plugins and hooks still load. They do not contain markers, so they do not change the result.
- Claude's answer is what the model reports. Treat an ORDER result as a hint and confirm it with `bin/capture-prompt <dir>`, which records the real request Claude sends (see MANUAL-CHECK.md), or with `/context` in an interactive session.

## Findings (2026-11-07, Claude Code 2.1.318)

Full run: `results/2026-11-07-first-run-claude.md`. Manual follow-up: `MANUAL-CHECK.md`.

**Everything the docs say about AGENTS.md held**, except one sentence about import order.

**`@import` puts the imported file after the parent, not first.** The docs say, about
`@AGENTS.md` at the top of CLAUDE.md: "Claude reads the imported file first, then the rest".
The real prompt shows the opposite. Three checks agree:

1. The lab's model report, 3 of 3 runs on haiku and sonnet: `C_ROOT` then `A_ROOT`.
2. `bin/capture-prompt`, which records the exact request Claude sends with no model call.
   Memory files arrive as separate `Contents of <path>` blocks inside a `<system-reminder>` in
   the first user message, not in the API `system` field. The CLAUDE.md block keeps the literal
   `@AGENTS.md` line. AGENTS.md is its own block, appended after it.
3. `/context all` in an interactive session lists `~/.claude/CLAUDE.md`, then `CLAUDE.md`, then
   `AGENTS.md`, each with its own token count. That list comes from the same loader that builds
   the prompt, in the same order.

Two controls rule out other explanations. With CLAUDE.md and AGENTS.md side by side and no
import, there is no AGENTS.md block at all, so the block above comes from the import. With
`@docs/style.md` inside AGENTS.md, the style file is also its own block after AGENTS.md. So
this is how every `@import` works, not something special about `@AGENTS.md`.

Practical effect: text below the import line is not "the rest after the import". It comes
before the imported file. If order matters to you, put the Claude-specific text where you want
it relative to that fact, and do not rely on the docs sentence.

### AGENTS.md is not a CLAUDE.md with another name

AGENTS.md is a second-class instruction file in Claude Code, by design. The docs say so, and
the lab confirmed every rule it checked. The table lists the differences and the evidence
behind each one.

| Behaviour | CLAUDE.md | AGENTS.md | Evidence |
|---|---|---|---|
| Loads when the other file exists at or above cwd | Always | Only when no CLAUDE.md or CLAUDE.local.md is there | Lab, docs |
| What triggers a subfolder file | Read, Write, Edit, `cat`/`head` via Bash | Read tool only | Lab (`cat` case verified), docs |
| Subfolder with both files | Wins | Skipped | Lab, docs |
| Local variant | `CLAUDE.local.md` is read | `AGENTS.local.md` is not | Lab, docs |
| Override variant | n/a | `AGENTS.override.md` is not read | Lab, docs |
| Dot folder | `.claude/CLAUDE.md` | `.claude/AGENTS.md` yes, `.agents/` no | Lab, docs |
| Turned off by a personal uncommitted file | No | Yes, a `CLAUDE.local.md` disables it | Lab, docs |
| `@import` expansion | Yes, after the parent | Yes, after the parent | Request capture |

Two traps follow from the combination of these rules:

- **The private file trap.** You keep one shared `AGENTS.md` for Codex and Claude, then add a
  `CLAUDE.local.md` with your own uncommitted notes. Claude silently stops reading `AGENTS.md`.
  The fix is Project instructions = `claude-md-and-agents-md`, or an `@AGENTS.md` import.
- **The shell trap.** Claude explores a subfolder with `cat`, `grep` or `ls`. A `CLAUDE.md` in
  that folder loads after a single-file `cat`. An `AGENTS.md` there stays unread until Claude
  uses the Read tool on a file in it.

Evidence standard by row: the import row is request level, no model in the loop
(`bin/capture-prompt`, plus `/context all`). Every other row is the model's own report, consistent
across runs, with no instruction file opened by Claude itself. See `MANUAL-CHECK.md` for the
import capture and `results/` for the runs.

Not verified yet: whether Write or Edit on a subfolder file triggers its `AGENTS.md` (docs name
only Read), and whether a subfolder `AGENTS.md` loads again after `/compact`.

## Sources

- [How Claude remembers your project: AGENTS.md](https://code.claude.com/docs/en/memory#agents-md)
- [Codex: AGENTS.md](https://developers.openai.com/codex/agent-configuration/agents-md)
- [Codex CLI reference: codex debug prompt-input](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
