# Host vs clean room

Host runs carry the machine's own `~/.claude/CLAUDE.md` and settings as a
constant. Container runs carry no agent configuration at all.

## claude

| arm | attribution host | attribution room | conventional host | conventional room | body host | body room |
|---|---|---|---|---|---|---|
| `attribution-custom` | 5/8 | 4/8 | 0/8 | 0/8 | 4/8 | 2/8 |
| `attribution-empty` | 0/8 | 0/8 | 0/8 | 0/8 | 2/8 | 1/8 |
| `attribution-empty-263` | - | 0/8 | - | 0/8 | - | 2/8 |
| `claudemd` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `claudemd-no-git-instructions` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `coauthoredby-false` | 0/8 | 0/8 | 0/8 | 0/8 | 4/8 | 2/8 |
| `control` | 8/16 | 3/16 | 0/16 | 0/16 | 4/16 | 1/16 |
| `control-cli-263` | - | 6/16 | - | 0/16 | - | 2/16 |
| `control-opus` | 8/8 | 8/8 | 0/8 | 0/8 | 5/8 | 0/8 |
| `git-hook` | 0/2 | 0/2 | 2/2 | 2/2 | 1/2 | 0/2 |
| `no-git-instructions` | 0/8 | 0/8 | 3/8 | 0/8 | 4/8 | 0/8 |
| `no-git-instructions-263` | - | 0/8 | - | 0/8 | - | 2/8 |
| `pretooluse-hook` | 0/2 | 0/2 | 1/2 | 2/2 | 2/2 | 0/2 |
| `sessionurl-true` | 0/2 | 0/2 | 0/2 | 0/2 | 0/2 | 0/2 |

## codex

| arm | attribution host | attribution room | conventional host | conventional room | body host | body room |
|---|---|---|---|---|---|---|
| `agents-md` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `agents-md-decoy` | 0/2 | 0/2 | 0/2 | 0/2 | 0/2 | 0/2 |
| `agents-override-md` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `control` | 0/8 | 0/8 | 8/8 | 0/8 | 8/8 | 0/8 |
| `developer-instructions` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `git-hook` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 0/2 |
| `model-instructions-file` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `pretooluse-hook` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 0/2 |

## opencode

| arm | attribution host | attribution room | conventional host | conventional room | body host | body room |
|---|---|---|---|---|---|---|
| `agents-md` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `agents-md-decoy` | 0/2 | 0/2 | 0/2 | 0/2 | 0/2 | 0/2 |
| `claude-md` | 0/2 | 0/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| `control` | 0/8 | 0/8 | 0/8 | 0/8 | 0/8 | 0/8 |
| `git-hook` | 0/2 | 0/2 | 2/2 | 2/2 | 0/2 | 0/2 |

## Attribution text seen in the clean room

- `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` — 9
- `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` — 8
- `Co-Authored-By: Robot <robot@example.com>` — 4
