# Results

Measured on one machine on 2026-08-18. Claude Code 2.1.234 on the host and
2.1.233 in the container; Codex 0.146.1 on the host and 0.147.0 in the
container; opencode 1.18.15 in both. Three runs per condition, and seven for
each of the four opencode rows that take the config directory apart, because
the first reading of those came out backwards and needed more evidence. 91
runs over 25 conditions. Every number below is produced by `scripts/report.rb`
from `results-raw/`, not typed by hand.

## The short version

Asking each CLI to reply with the word `OK`, on this machine and in a fresh
container:

| | On this machine | Fresh container | What the machine adds |
|---|---:|---:|---:|
| Claude Code | 59,354 | 30,265 | 29,089 (1.96x) |
| Codex | 28,410 | 12,212 | 16,198 (2.33x) |
| opencode | 33,935 | 5,903 | 28,032 (5.75x) |

opencode has by far the lightest harness of the three and by far the heaviest
configuration on top of it. Its container floor is a fifth of Claude's, and this
machine still turns it into the second-largest prompt of the three.

Codex and opencode both ran on `gpt-5.6-sol`, so that pair is a like-for-like
comparison: same model, different harness. Codex sends 28,410 and opencode
33,935 for the same one-word answer.

That floor is not paid once. It is the smallest any request in that session can
be.

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
| opencode | `host-project` | 3 | 34,042 | 33,997-34,071 | 5.77x | the same machine, inside a real project |
| opencode | `host-full` | 3 | 33,935 | 33,906-34,097 | 5.75x | the machine as it is, in a directory with no project files |
| opencode | `host-config-short-path` | 7 | 33,883 | 33,745-33,930 | 5.74x | the same symlinked config, at a short path instead of a long temporary one |
| opencode | `host-config-relocated` | 7 | 36,271 | 36,102-36,706 | 6.14x | the real config directory, reached through a symlink at a temporary path |
| opencode | `host-config-rebuilt` | 7 | 35,925 | 35,452-36,845 | 6.09x | the same rebuilt config directory as host-no-mcp, with the MCP servers left in |
| opencode | `host-no-mcp` | 7 | 35,833 | 35,430-36,502 | 6.07x | MCP servers off, everything else on |
| opencode | `host-pure` | 3 | 32,615 | 32,557-32,675 | 5.53x | external plugins off, everything else on |
| opencode | `host-no-config` | 3 | 20,444 | 20,380-20,477 | 3.46x | ~/.config/opencode not read: no config, skills, agents or commands |
| opencode | `host-leanest` | 3 | 20,451 | 20,268-20,463 | 3.46x | no config directory and no external plugins |
| opencode | `container` | 3 | 5,903 | 0 | 1.00x | a fresh container: a freshly installed CLI and nothing else |

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
| opencode | MCP servers | `host-config-rebuilt` minus `host-no-mcp` | 92 |
| opencode | Moving XDG_CONFIG_HOME to a long path | `host-config-relocated` minus `host-config-short-path` | 2,388 |
| opencode | Rebuilding the config directory entry by entry | `host-config-rebuilt` minus `host-config-relocated` | -346 |
| opencode | External plugins | `host-full` minus `host-pure` | 1,320 |
| opencode | The ~/.config/opencode directory | `host-full` minus `host-no-config` | 13,491 |
| opencode | Config directory and plugins together | `host-full` minus `host-leanest` | 13,484 |
| opencode | Being inside a real project | `host-project` minus `host-full` | 107 |

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
| opencode | `host-project` | 0.0000 | 10.1 |
| opencode | `host-full` | 0.0000 | 20.3 |
| opencode | `host-config-short-path` | 0.0000 | 5.3 |
| opencode | `host-config-relocated` | 0.0000 | 5.5 |
| opencode | `host-config-rebuilt` | 0.0000 | 5.5 |
| opencode | `host-no-mcp` | 0.0000 | 9.6 |
| opencode | `host-pure` | 0.0000 | 57.8 |
| opencode | `host-no-config` | 0.0000 | 59.6 |
| opencode | `host-leanest` | 0.0000 | 48.9 |
| opencode | `container` | 0.0000 | 9.2 |

### Installed surface on the host, read off disk

| Agent | Item | Value |
|---|---|---:|
| claude | global memory file (`CLAUDE.md`) | 1,378 bytes |
| claude | skill directories | 87 |
| claude | installed plugins | 20 |
| claude | MCP servers configured by hand | 2 |
| claude | session hooks configured | 2 |
| claude | `~/.claude.json` | 327,089 bytes, 137 project entries |
| codex | global memory file (`AGENTS.md`) | 28,338 bytes (~7,085 tokens) |
| codex | `config.toml` | 15,117 bytes, 85 project entries |
| codex | MCP servers in config | 8 |
| codex | skill directories | 130 |
| codex | agent definitions | 20 |
| codex | saved prompts | 48 |
| opencode | `opencode.json` | 2,087 bytes |
| opencode | skill directories | 54 |
| opencode | agent definitions | 29 |
| opencode | MCP servers in config | 1 |
| opencode | plugin entries | 2 |

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

What MCP still costs is time and reliability. Of the eight servers exactly one
connected: one failed outright, four needed authentication and two were still
pending when the answer arrived. That accounting comes from Claude's `init`
event, not from stderr: Claude wrote nothing to stderr in any of its 30 runs.

Codex shows the same unreliability and is the only one of the three that
writes it down. Two of its servers logged transport failures in one host run
of twelve. Its other stderr lines, present in every run including the
container, are `failed to refresh available models`, which is not MCP.
opencode's stderr was empty in all 46 runs.

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

The flag reads as "start fresh". It removes **2,672 tokens** of the 16,198 that
this machine adds. `~/.codex/AGENTS.md` is 28,338 bytes, roughly 7,000 tokens,
and it loads anyway; so do the 130 skills, and the truncation warning still
fires. The only condition that produced a genuinely bare Codex was the
container.

### Only one of the three notices which project it is in

Opening the same folder cost Claude **2,243 extra tokens**, and that is the
only one of the three differences big enough to be real. Codex's is **447**
(`host-project` 28,857 against `host-full` 28,410) and its run-to-run spread
on those two conditions is 573 and 593, so 447 sits inside its own noise.
opencode's is **107** against spreads of 74 and 191, and sits inside its noise
too.

What separates them is what each agent reads. The project keeps its
instructions in `CLAUDE.md`, which Codex does not read. Its `AGENTS.md` is 22
bytes long and says `Read @Claude.md file`, which is an instruction, not
content: Codex starts the session knowing nothing about the project and has to
spend a tool call to find out.

### opencode: the lightest harness carrying the heaviest load

opencode in a fresh container sends **5,903 tokens** to answer `OK`. That is less
than half what Codex sends from the same kind of container and a fifth of
Claude's floor. Whatever opencode ships as its own system prompt and built-in
tools, it is small.

On this machine the same command sends **33,935**. The configuration is 4.75
times the size of the program it configures, which makes the whole prompt 5.75
times what a bare install sends.

Almost all of it is one directory. Taking `~/.config/opencode` away, which
removes the config file, 54 skills, 29 agents and 3 commands in one move, drops
the prompt to **20,444**: a saving of **13,491 tokens**, 48% of everything the
machine adds. External plugins account for another 1,320.

That still leaves about 14,500 tokens between the stripped host run and the
container floor that no available switch removes.

### The result that came out backwards was measuring the wrong thing

Read against `host-full`, removing opencode's one MCP server appeared to make
the prompt **1,898 tokens bigger**, over seven runs with a spread of 1,072. The
number was solid. It was not a number about MCP.

opencode has no flag that suppresses its servers for one run, so `host-no-mcp`
cannot remove a layer the way every other row does. It has to build a config
directory: write `opencode.json` out again without its `mcp` key, symlink every
other entry to the real one, and point `XDG_CONFIG_HOME` at the result. That
changes two things at once, and only one of them is MCP.

Three controls separate them. Each runs seven times, like the row it explains.

| Condition | What it changes | Median |
|---|---|---:|
| `host-full` | nothing; the real config directory | 33,935 |
| `host-config-short-path` | the same config, reached through a symlink at `/tmp/lxo` | 33,883 |
| `host-config-relocated` | the same config, through a symlink at a long temporary path | 36,271 |
| `host-config-rebuilt` | the full rebuild, MCP left in | 35,925 |
| `host-no-mcp` | the full rebuild, MCP removed | 35,833 |

Reading down the differences:

| Step | Tokens |
|---|---:|
| Config at a short path instead of the real one | -52 |
| Long path instead of short path | **+2,388** |
| Taking the directory apart entry by entry | -346 |
| Removing the MCP server | **-92** |

opencode's run-to-run spread on these conditions is 185 to 1,393, so -52, -346
and -92 are all nothing. **+2,388 is everything.** The published -1,898 was the
path move minus a rounding error wearing MCP's name.

So opencode's MCP server costs about what Claude's eight cost (501) and what
Codex's eight cost (25): nothing worth counting. All three agents agree, and
the disagreement was an artifact of the one measurement that had to build its
own environment.

### Where you keep opencode's config changes what every request costs

The +2,388 is not a quirk of the harness. It reproduces on demand and the
arithmetic closes.

`Dir.mktmpdir` hands out a path 91 characters long. `/tmp/lxo` is 8. That is 83
extra characters, and this machine's opencode config holds 54 skills, 29 agents
and 3 commands, which is 86 items:

```
2,388 tokens / 86 items      = 27.8 tokens per item
83 characters / 27.8 tokens  = 2.99 characters per token
```

Three characters per token is what a tokenizer gives a string like
`llmx-opencode-config-20260818-15568-s0qsqt`. So opencode writes the absolute
path of each config item into the prompt, once per item, and the length of
`XDG_CONFIG_HOME` is multiplied by however many items live under it.

Two machines with byte-identical opencode configurations therefore pay
different amounts per request, and the thing that separates them is how deep
the config directory sits. Nothing in opencode reports this, and no flag
changes it.

It also means the measurement rule this experiment started from has an edge
nobody expected: a condition that relocates a directory has not held everything
else fixed, because for opencode the location *is* one of the things being
measured.

### opencode tells you the least about itself

Claude emits an `init` event that names every tool, skill, subagent, plugin and
MCP server it attached. Codex says nothing about what it loaded, but it does
speak up when it truncates. opencode does neither.

| | Claude Code | Codex | opencode |
|---|---|---|---|
| Says what it loaded | item by item | nothing | nothing |
| Warns when it truncates | no | yes | no |
| MCP off for one run | `--strict-mcp-config` | `-c mcp_servers={}` | config file only |
| Skills off for one run | `--disable-slash-commands` | no | config file only |
| Subagents off for one run | only by refusing `Task` | no | no |
| Everything off for one run | `--safe-mode` | no | `--pure`, and only partly |
| Session not written | `--no-session-persistence` | `--ephemeral` | no |

Every opencode number here had to be produced by taking a directory away and
running the whole thing again, because there is no flag that isolates a layer
and no event that reports one.

### The same field name means three different things

Getting this wrong produced a wrong result in this experiment before it was
caught, so it belongs in the results rather than in a footnote.

| CLI | Field | Cached tokens |
|---|---|---|
| Claude Code | `input_tokens` | separate; `cache_read` and `cache_creation` are added to it |
| Codex | `input_tokens` | included; `cached_input_tokens` is a subset |
| opencode | `tokens.input` | **excluded**; `tokens.cache.read` has to be added back |

Reading opencode's `input` alone split every condition into two clusters about
35% apart. It looked exactly like a CLI loading different things on different
runs: three `host-full` runs reported 33,935 with no cache, then 22,130 and
22,321 each with precisely 11,776 cache reads. 22,130 + 11,776 = 33,906.

`parse_probe.rb` now fails loudly when repeats of one condition disagree by more
than 10%, because from the outside that is what a parser summing the wrong
fields looks like.

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
| Prune `~/.config/opencode`: 54 skills, 29 agents, 3 commands | up to 13,491 | always for opencode; it is 48% of everything that machine adds |
| `--pure` for opencode | 1,320 | a run that needs no plugin |
| Leave opencode's MCP server alone | ~0 tokens | it was never the problem; the row that said otherwise was measuring a path move |
| Keep opencode's config directory at a short path | ~28 tokens per item per request | always; a deep path is multiplied by every skill, agent and command under it |

**When it is worth measuring at all.** The startup context is a floor under
every request in a session, so it matters in proportion to how many requests
you make and how small the window is. On a 1M-token model 59,354 tokens is 6%
of the window. On a 200k model it is 30% of it, before the task is read.

**And measure rather than assume which layer is heavy.** The three agents do
not agree on where the weight sits. On Claude it is the subagent catalogue
(18,368). On opencode it is one config directory (13,491), plus the length of
the path that directory sits at (2,388 here). MCP is nearly free on all three:
501, 25 and about zero. Advice that names a layer without naming an agent and a
version is guessing.

## What this does not show

- **Whether any of it helps.** This experiment counts what is loaded. It says
  nothing about whether 175 skills and 38 subagents make the agent better at
  real work. A skill that saves one wrong turn can be worth its weight many
  times over.
- **Whether the cost is real money.** Three runs of `claude/host-leanest` sent
  28,686, 28,686 and 28,687 tokens and cost $0.1722, $0.0526 and $0.0526: the
  same prompt at the same size for three times the price, with nothing between
  the runs except whether an earlier one had warmed the cache. The token counts
  are stable; the dollar figures in the table are not comparable across rows and
  are printed only to show the range.
- **Anything about other machines.** One developer, one day, one set of
  installed plugins and skills.
- **How far the path-length finding generalises.** It is established here, on
  one config directory holding 86 items, and the arithmetic is clean. Whether
  other agents embed config paths the same way was not tested; Claude and Codex
  were never run from a relocated config directory, because neither of them
  needed one.
- **A like-for-like container floor for opencode.** Claude and Codex come from
  the shared base image; opencode's floor is that image plus one npm package,
  because the base does not carry opencode yet.
