# Results

## claude

| arm | n | attribution | conventional | has body | mentions AI | median subject len |
|---|---|---|---|---|---|---|
| `attribution-custom` | 8 | 4/8 | 0/8 | 2/8 | 0/8 | 44 |
| `attribution-empty-263` | 8 | 0/8 | 0/8 | 2/8 | 0/8 | 44 |
| `attribution-empty` | 8 | 0/8 | 0/8 | 1/8 | 0/8 | 44 |
| `claudemd-no-git-instructions` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 46 |
| `claudemd` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 49 |
| `coauthoredby-false` | 8 | 0/8 | 0/8 | 2/8 | 0/8 | 44 |
| `control-cli-263` | 16 | 6/16 | 0/16 | 2/16 | 6/16 | 44 |
| `control-opus` | 8 | 8/8 | 0/8 | 0/8 | 8/8 | 40 |
| `control` | 16 | 3/16 | 0/16 | 1/16 | 3/16 | 44 |
| `git-hook` | 2 | 0/2 | 2/2 | 0/2 | 0/2 | 61 |
| `no-git-instructions-263` | 8 | 0/8 | 0/8 | 2/8 | 0/8 | 43 |
| `no-git-instructions` | 8 | 0/8 | 0/8 | 0/8 | 0/8 | 43 |
| `pretooluse-hook` | 2 | 0/2 | 2/2 | 0/2 | 0/2 | 53 |
| `sessionurl-true` | 2 | 0/2 | 0/2 | 0/2 | 0/2 | 40 |

## codex

| arm | n | attribution | conventional | has body | mentions AI | median subject len |
|---|---|---|---|---|---|---|
| `agents-md-decoy` | 2 | 0/2 | 0/2 | 0/2 | 0/2 | 42 |
| `agents-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 39 |
| `agents-override-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 40 |
| `control` | 8 | 0/8 | 0/8 | 0/8 | 0/8 | 45 |
| `developer-instructions` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 41 |
| `git-hook` | 2 | 0/2 | 2/2 | 0/2 | 0/2 | 54 |
| `model-instructions-file` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 42 |
| `pretooluse-hook` | 2 | 0/2 | 2/2 | 0/2 | 0/2 | 54 |

## opencode

| arm | n | attribution | conventional | has body | mentions AI | median subject len |
|---|---|---|---|---|---|---|
| `agents-md-decoy` | 2 | 0/2 | 0/2 | 0/2 | 0/2 | 52 |
| `agents-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 44 |
| `claude-md` | 2 | 0/2 | 2/2 | 2/2 | 0/2 | 45 |
| `control` | 8 | 0/8 | 0/8 | 0/8 | 0/8 | 35 |
| `git-hook` | 2 | 0/2 | 2/2 | 0/2 | 0/2 | 37 |

## Attribution text actually produced

- `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` — 9 time(s)
- `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` — 8 time(s)
- `Co-Authored-By: Robot <robot@example.com>` — 4 time(s)

## Trials that failed to commit
(none)
