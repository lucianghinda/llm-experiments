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
