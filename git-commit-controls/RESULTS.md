# Results

## claude

| arm | n | attribution | conventional | has body | mentions AI | median subject len |
|---|---|---|---|---|---|---|
| `attribution-custom` | 8 | 5/8 | 0/8 | 4/8 | 0/8 | 44 |
| `attribution-empty` | 8 | 0/8 | 0/8 | 2/8 | 0/8 | 44 |
| `claudemd-no-git-instructions` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 49 |
| `claudemd` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 46 |
| `coauthoredby-false` | 8 | 0/8 | 0/8 | 4/8 | 0/8 | 44 |
| `control-opus` | 8 | 8/8 | 0/8 | 5/8 | 8/8 | 35 |
| `control` | 16 | 8/16 | 0/16 | 4/16 | 8/16 | 44 |
| `git-hook` | 2 | 0/2 | 2/2 | 1/2 | 0/2 | 55 |
| `no-git-instructions` | 8 | 0/8 | 3/8 | 4/8 | 0/8 | 44 |
| `pretooluse-hook` | 2 | 0/2 | 1/2 | 2/2 | 0/2 | 48 |
| `sessionurl-true` | 2 | 0/2 | 0/2 | 0/2 | 0/2 | 44 |

## codex

| arm | n | attribution | conventional | has body | mentions AI | median subject len |
|---|---|---|---|---|---|---|
| `agents-md-decoy` | 2 | 0/2 | 0/2 | 0/2 | 0/2 | 40 |
| `agents-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 39 |
| `agents-override-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 44 |
| `control` | 8 | 0/8 | 8/8 | 8/8 | 0/8 | 39 |
| `developer-instructions` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 39 |
| `git-hook` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 44 |
| `model-instructions-file` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 39 |
| `pretooluse-hook` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 39 |

## opencode

| arm | n | attribution | conventional | has body | mentions AI | median subject len |
|---|---|---|---|---|---|---|
| `agents-md-decoy` | 2 | 0/2 | 0/2 | 0/2 | 0/2 | 27 |
| `agents-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 41 |
| `claude-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 41 |
| `control` | 8 | 0/8 | 0/8 | 0/8 | 0/8 | 37 |
| `git-hook` | 2 | 0/2 | 2/2 | 0/2 | 0/2 | 44 |

## Attribution text actually produced

- `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` — 8 time(s)
- `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` — 8 time(s)
- `Co-Authored-By: Robot <robot@example.com>` — 5 time(s)

## Trials that failed to commit
(none)
