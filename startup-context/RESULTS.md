# Results

Measured on one machine on 2026-08-18. Claude Code 2.1.234 on the host and
2.1.233 in the container; Codex 0.146.1 on the host and 0.147.0 in the
container. Three runs per condition. Every number below is produced by
`scripts/report.rb` from `results-raw/`, not typed by hand.

## The short version

Asking Claude Code to reply with the word `OK` sends **59,354 tokens** on this
machine. The same question in a fresh container sends **30,265**. Codex sends
**28,410** on the machine and **12,212** in the container.

So on this setup the machine roughly doubles Claude's floor and more than
doubles Codex's. That floor is not paid once. It is the smallest any request in
that session can be.

## The tables

### Startup context: what arrives before the first token of work

| Agent | Condition | Runs | Startup tokens (median) | Spread | Times the container floor | What it is |
|---|---|---:|---:|---:|---:|---|
| claude | `host-project` | 3 | 61,597 | 61,595-61,599 | 2.04x | the same machine, inside a real project |
| claude | `host-full` | 3 | 59,354 | 59,349-59,539 | 1.96x | the machine as it is, in a directory with no project files |
| claude | `host-default-model` | 3 | 48,421 | 48,421-48,537 | 1.60x | the machine as it is, on whatever model the machine picks by default |
| claude | `host-no-mcp` | 3 | 58,853 | 58,848-58,856 | 1.94x | MCP servers off, everything else on |
| claude | `host-no-skills` | 3 | 47,929 | 47,589-47,939 | 1.58x | skills and slash commands off, everything else on |
| claude | `host-no-subagents` | 3 | 40,986 | 40,795-40,996 | 1.35x | the Task tool and the subagent catalogue it carries, off |
| claude | `host-lean` | 3 | 47,235 | 47,232-47,239 | 1.56x | both of the above off together |
| claude | `host-leanest` | 3 | 28,686 | 28,686-28,687 | 0.95x | MCP, skills and subagents all off, hooks and CLAUDE.md still on |
| claude | `host-safe-mode` | 3 | 29,135 | 29,133-29,136 | 0.96x | every customisation off: CLAUDE.md, skills, plugins, hooks, MCP, agents |
| claude | `container` | 3 | 30,265 | 0 | 1.00x | a fresh container: a freshly installed CLI and nothing else |
| codex | `host-project` | 3 | 28,857 | 28,285-28,858 | 2.36x | the same machine, inside a real project |
| codex | `host-full` | 3 | 28,410 | 28,247-28,840 | 2.33x | the machine as it is, in a directory with no project files |
| codex | `host-no-mcp` | 3 | 28,385 | 28,239-28,669 | 2.32x | MCP servers off, everything else on |
| codex | `host-no-config` | 3 | 25,738 | 25,738-25,885 | 2.11x | ~/.codex/config.toml not read; AGENTS.md and skills still are |
| codex | `container` | 3 | 12,212 | 12,211-12,787 | 1.00x | a fresh container: a freshly installed CLI and nothing else |

### What Claude reports loading, per condition

Claude emits an `init` event naming everything it attached. These are counts from that event, one representative run per condition.

| Condition | Tools | MCP servers | Skills | Slash commands | Subagents | Plugins | Hooks fired |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `host-project` | 32 | 8 | 197 | 260 | 38 | 17 | 5 | 12,099 |
| `host-full` | 32 | 8 | 175 | 238 | 38 | 17 | 5 | 12,099 |
| `host-default-model` | 35 | 8 | 175 | 238 | 38 | 17 | 5 | 12,099 |
| `host-no-mcp` | 27 | 0 | 175 | 238 | 38 | 17 | 5 | 12,099 |
| `host-no-skills` | 31 | 8 | 0 | 0 | 38 | 17 | 5 | 12,099 |
| `host-no-subagents` | 31 | 8 | 175 | 238 | 38 | 17 | 5 | 12,099 |
| `host-lean` | 26 | 0 | 0 | 0 | 38 | 17 | 5 | 12,099 |
| `host-leanest` | 25 | 0 | 0 | 0 | 38 | 17 | 5 | 12,099 |
| `host-safe-mode` | 26 | 0 | 16 | 48 | 4 | 17 | 0 | 0 |
| `container` | 21 | 0 | 14 | 40 | 5 | 0 | 0 | 0 |

### What each layer costs

Each row is the difference between two conditions that are identical apart from one layer.

| Agent | Layer | Measured as | Tokens |
|---|---|---|---:|
| claude | MCP servers | `host-full` minus `host-no-mcp` | 501 |
| claude | Skills and slash commands | `host-full` minus `host-no-skills` | 11,425 |
| claude | Subagent catalogue and the Task tool | `host-full` minus `host-no-subagents` | 18,368 |
| claude | MCP, skills and subagents together | `host-full` minus `host-leanest` | 30,668 |
| claude | MCP + skills together | `host-full` minus `host-lean` | 12,119 |
| claude | Everything the user added | `host-full` minus `host-safe-mode` | 30,219 |
| claude | Being inside a real project | `host-project` minus `host-full` | 2,243 |
| codex | MCP servers | `host-full` minus `host-no-mcp` | 25 |
| codex | config.toml and AGENTS.md | `host-full` minus `host-no-config` | 2,672 |
| codex | Being inside a real project | `host-project` minus `host-full` | 447 |

### Cost and wall time of saying "OK"

Cost moves with the prompt cache, so it is reported and not compared. Token counts do not move.

| Agent | Condition | Median cost (USD) | Median wall (s) |
|---|---|---:|---:|
| claude | `host-project` | 0.1990 | 18.4 |
| claude | `host-full` | 0.2170 | 13.6 |
| claude | `host-default-model` | 0.3333 | 7.6 |
| claude | `host-no-mcp` | 0.2140 | 7.8 |
| claude | `host-no-skills` | 0.1520 | 10.7 |
| claude | `host-no-subagents` | 0.1228 | 12.6 |
| claude | `host-lean` | 0.1478 | 10.9 |
| claude | `host-leanest` | 0.0526 | 9.9 |
| claude | `host-safe-mode` | 0.0366 | 6.6 |
| claude | `container` | 0.0091 | 7.3 |
| codex | `host-project` | not reported | 51.8 |
| codex | `host-full` | not reported | 77.6 |
| codex | `host-no-mcp` | not reported | 58.0 |
| codex | `host-no-config` | not reported | 43.2 |
| codex | `container` | not reported | 57.1 |

### Installed surface on the host, read off disk

| Agent | Item | Value |
|---|---|---:|
| claude | global memory file (`CLAUDE.md`) | 1,378 bytes |
| claude | skill directories | 87 |
| claude | installed plugins | 20 |
| claude | MCP servers configured by hand | 2 |
| claude | session hooks configured | 2 |
| claude | `~/.claude.json` | 327,378 bytes, 137 project entries |
| codex | global memory file (`AGENTS.md`) | 28,338 bytes (~7,085 tokens) |
| codex | `config.toml` | 15,017 bytes, 84 project entries |
| codex | MCP servers in config | 8 |
| codex | skill directories | 130 |
| codex | agent definitions | 20 |
| codex | saved prompts | 48 |

### What the CLIs said about their own load

- Skill descriptions were shortened to fit the 2% skills context budget. Codex can still see every skill, but some descriptions are shorter. Disable unused skills or plugins to leave more room for the rest.

## What the numbers say

### The most expensive thing is the one with no counter

Claude's interface shows how many MCP servers are connected. It does not show
what the subagent catalogue costs. On this machine that catalogue is **18,368
tokens**, 31% of the whole startup context, and it is 36 times more expensive
than all eight MCP servers together.

The catalogue is 38 subagents, nearly all of them arriving through installed
plugins, and it ships inside the description of the `Task` tool. Several of the
descriptions carry two or three worked `<example>` blocks. Those examples exist
to help a model choose the right agent, and every one of them is paid for on
every request whether an agent is used or not.

### MCP is no longer the expensive part

Eight MCP servers cost **501 tokens**. That is not a typo and it is not a
mistake in the measurement: `host-full` reported 8 servers and `host-no-mcp`
reported 0, and the difference between them is 501 tokens.

The reason is tool deferral. Only 5 MCP tools appear in the tool list; the rest
are held behind `ToolSearch` and their schemas load when asked for. Advice
written before that mechanism existed no longer describes what MCP costs.

What MCP still costs is time and reliability. Of the eight servers, one failed
outright and four needed authentication. On Codex the same picture appears in
stderr: two servers logged transport failures on every host run.

### Hooks spend context nobody asked for

Five `SessionStart` hooks fire before the first request and write **12,099
bytes** into the conversation, about 3,000 tokens. One hook contributes 10,793
of those bytes on its own. There is no per-run flag that turns hooks off short
of `--safe-mode`, which turns everything else off with them.

### Three flags get a fully loaded machine below a bare container

`--strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands
--disallowed-tools Task` takes the same machine from 59,354 to **28,686**
tokens. That is 1,579 tokens *below* the fresh container, which still has its
own Task tool, subagents and skills.

The customisations are not the problem. Carrying all of them into every session
is.

### The model changes the answer

Same machine, same configuration, same prompt. Pinned to `claude-sonnet-5` the
startup context is 59,354 tokens. Left to pick for itself, the machine chose
`claude-opus-5[1m]` and sent **48,421**, which is 10,933 fewer while exposing *more* tools
(35 against 32).

Whatever the reason, it means a startup-context number is only true for the
model it was measured on.

### The same command does not load the same thing twice

Across three identical `host-full` runs the reported MCP server count was 8, 4
and 4. In `host-no-skills` the tool count moved between 26 and 31. Nothing
changed between the runs except which servers happened to answer in time.

An agent's tool surface on this machine is a race, not a configuration.

### Codex is already over its own budget

Every host run of Codex emitted this, and no container run did:

> Skill descriptions were shortened to fit the 2% skills context budget. Codex
> can still see every skill, but some descriptions are shorter. Disable unused
> skills or plugins to leave more room for the rest.

There are 130 skill directories under `~/.codex/skills`. Codex is truncating
their descriptions to protect the rest of the prompt, which means the machine
is past the point where adding a skill makes the others easier to find.

### `--ignore-user-config` does not give you a clean Codex

The flag reads as "start fresh". It removes **2,672 tokens** of the 16,199 that
this machine adds. `~/.codex/AGENTS.md` is 28,338 bytes, roughly 7,000 tokens,
and it loads anyway; so do the 130 skills, and the truncation warning still
fires. The only condition that produced a genuinely bare Codex was the
container.

### The same project directory feeds the two agents very differently

Opening the same folder cost Claude **2,243 extra tokens** and Codex about
**six**. The project keeps its instructions in `CLAUDE.md`, which Codex does not
read. Its `AGENTS.md` is 22 bytes long and says `Read @Claude.md file`, which is
an instruction, not content: Codex starts the session knowing nothing about the
project and has to spend a tool call to find out.

## What to change, and when

| Change | Recovers | Worth doing when |
|---|---|---|
| Uninstall plugins that ship subagent fleets you do not use | up to 18,368 | always; this is the largest single item and the least visible |
| `--disallowed-tools Task` | 18,368 | the task is narrow and you will not delegate |
| `--disable-slash-commands` | 11,425 | mechanical work where no skill will be invoked |
| Audit `SessionStart` hooks | ~3,000 | any hook writing kilobytes into every session |
| Remove MCP servers that fail or need auth | ~0 tokens, real seconds | they cost startup time and fill stderr, not context |
| Trim `~/.codex/AGENTS.md` (28 KB) and prune 130 Codex skills | up to ~16,000 | Codex already says it is truncating |
| Give a project a real `AGENTS.md` instead of a pointer | n/a | you use Codex on a project whose rules live in `CLAUDE.md` |

**When it is worth measuring at all.** The startup context is a floor under
every request in a session, so it matters in proportion to how many requests
you make and how small the window is. On a 1M-token model 59,354 tokens is 6%
of the window. On a 200k model it is 30% of it, before the task is read.

## What this does not show

- **Whether any of it helps.** This experiment counts what is loaded. It says
  nothing about whether 175 skills and 38 subagents make the agent better at
  real work. A skill that saves one wrong turn can be worth its weight many
  times over.
- **Whether the cost is real money.** Prompt caching means an identical prompt
  can cost 24 times more or less depending on whether an earlier run warmed the
  cache. The token counts are stable; the dollar figures in the table are not
  comparable across rows and are printed only to show the range.
- **Anything about other machines.** One developer, one day, one set of
  installed plugins.
