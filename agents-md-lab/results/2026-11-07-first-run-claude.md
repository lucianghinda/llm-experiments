# First run: Claude Code (7 Nov 2026)

Claude Code 2.1.319, model haiku (import order also checked with sonnet).
Run in a cloud sandbox with a default user config. Codex was not installed there, so its column still needs a run on the Mac: `bin/lab --tool codex`.

| Result | Scenario | Expected (docs) | Got |
|---|---|---|---|
| PASS | agents-only | A_ROOT | A_ROOT |
| PASS | claude-and-agents | C_ROOT | C_ROOT |
| ORDER | claude-imports-agents | A_ROOT, C_ROOT | C_ROOT, A_ROOT (3 of 3 runs, haiku and sonnet) |
| PASS | local-turns-agents-off | L_ROOT | L_ROOT |
| PASS | local-with-and-setting | L_ROOT, A_ROOT | L_ROOT, A_ROOT |
| PASS | nested-launch-in-subfolder | A_ROOT, A_APP | A_ROOT, A_APP |
| PASS | dot-claude-agents | A_DOTCLAUDE | A_DOTCLAUDE |
| PASS | override-file | A_ROOT | A_ROOT |
| PASS | agents-local-and-dot-agents | A_ROOT | A_ROOT |
| PASS | import-inside-agents | A_ROOT, STYLE | A_ROOT, STYLE |
| PASS | subfolder-on-read | A_ROOT, A_PKG | A_ROOT, A_PKG |
| PASS | subfolder-on-cat | A_ROOT | A_ROOT (the cat did run) |
| PASS | subfolder-claude-on-cat | A_ROOT, C_PKG | A_ROOT, C_PKG |
| PASS | subfolder-with-own-claude | A_ROOT, C_PKG | A_ROOT, C_PKG |
| PASS | codex-fallback-name | none | none |

## Findings

1. Everything the docs say about AGENTS.md held, including the two less obvious rules: a CLAUDE.local.md switches AGENTS.md off, and a subfolder AGENTS.md loads after a Read but not after a `cat`, while a subfolder CLAUDE.md loads after both.
2. One difference: with `@AGENTS.md` at the top of CLAUDE.md, the docs say Claude reads the imported file first. In every run Claude reported the CLAUDE.md marker before the imported one. This is the order Claude reports, not proof of the real layout, so check it in an interactive session with `/context` before posting about it.

## Follow-up 2026-11-07

Finding 2 checked with `bin/capture-prompt` (real request, no model call): CLAUDE.md block first with the literal `@AGENTS.md` line kept, AGENTS.md appended as its own block after it. The ORDER result was the real layout. Details in MANUAL-CHECK.md.
