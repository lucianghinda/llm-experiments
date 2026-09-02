# Prompts and harness, exactly as run

Date of runs: 2026-09-02. Claude Code 2.1.258, model `claude-opus-5`.

The four targets are the same four the
[`simplified-technical-english/`](../simplified-technical-english/) experiment used, and
the verbatim copy of each one under test is kept there rather than duplicated here:
`../simplified-technical-english/<target>/00-source-*.rb`.

## The base sentences

One per target, identical across all twelve variants except where the variant
itself edits it. `%{slot}` and `%{trail}` are empty in variants 1–9.

| Target | Base sentence |
|---|---|
| 01-rails-concern | `Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me%{slot} how it works.%{trail}` |
| 02-single-method-domain | ``Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app and explain to me%{slot} how it works.%{trail}`` |
| 03-single-method-algorithm | ``Read the method `count_transpositions` in app/services/authors/match_by_name.rb in this Rails app and explain to me%{slot} how it works.%{trail}`` |
| 04-query-object | `Read the file app/services/edition/draft_query.rb in this Rails app and explain to me%{slot} how it works.%{trail}` |

Unlike the earlier experiment there is no "write your answer to this file"
block: `-p` prints the final message to stdout, and the harness captures it.
That removes the old asymmetry between agents, and the prompts can say "this
Rails app" because a main-loop session has a working directory.

## The variants

| Slug | `outputStyle` setting | Prompt edit |
|---|---|---|
| 01-default | (none — the setting is absent) | — |
| 02-concise | `Concise` | — |
| 03-explanatory | `Explanatory` | — |
| 04-learning | `Learning` | — |
| 05-proactive | `Proactive` | — |
| 06-style-ste | `Simple Technical English` | — |
| 07-style-asd | `ASD-STE100` | — |
| 08-style-asd-hatch | `ASD-STE100 escape hatch` | — |
| 09-style-asd-bare | `ASD-STE100 bare` | — |
| 10-prompt-ste | (none) | slot = ` in Simple Technical English` |
| 11-prompt-asd | (none) | slot = ` in ASD-STE100 Simplified Technical English` |
| 12-prompt-asd-hatch | (none) | trail = ` Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning.` |

Custom style files (variants 6–9) are committed verbatim in
[`styles/`](styles/) and are copied into the app's `.claude/output-styles/`
before the session starts. The setting is written to
`.claude/settings.local.json` in the app checkout.

## The harness

Each cell is one fresh container from `llmx-base` (see
[`../containers/`](../containers/)), one `claude -p` main-loop session, then
the container is deleted. Main-loop rather than subagent, because output
styles do not apply to subagents. Clean room rather than the host, because
the host's global `~/.claude/CLAUDE.md` itself says "Use Simple Technical
English", which would hand the treatment to the control.

Disk frugality shaped the harness (the machine ran at 97% full):

- **No per-app images.** The apps arrive as git bundles of their `main`
  branches (10 MB total, versus ~5 GB per app image plus a BuildKit cache),
  cloned inside the container at trial start. A bundle carries committed
  history only, so untracked host files cannot leak in.
- **The CLI is newer than the base image's.** The base pins Claude Code
  2.1.233; the Concise style needs ≥ 2.1.237. Rather than rebuild the base,
  Claude Code was installed once into `~/.llmx/tools/claude-latest` from
  inside a container (so the binaries are linux-arm64) and that directory is
  mounted read-only into every trial.
- **One container at a time**, `--rm`, 4 GB memory. Nothing persists between
  trials except the results.

The invocation, from the checkout root:

```
claude -p "<prompt>" --model opus --output-format json \
  --strict-mcp-config --mcp-config /tmp/empty-mcp.json
```

- `--strict-mcp-config` with an empty config, because **both app repos commit
  a `.mcp.json`** whose servers run through `bundle exec`; no gems are
  installed in these trials, so the servers would fail noisily and dirty the
  context. Zero MCP is also the clean-room guarantee.
- The repos' own committed `CLAUDE.md`, `AGENTS.md`, `.claude/rules/` and
  `.claude/settings.json` files are left in place, matching the earlier
  experiment's "the codebase's own instructions are part of the codebase"
  stance. Neither carries an `outputStyle`, which was checked before running.
- Credentials are copied from the mounted seed into a container-local
  `CLAUDE_CONFIG_DIR` (three files: `.credentials.json`, `.claude.json`,
  `settings.json` — the last contains only a theme), so the seed is never
  written.

Per cell, three files are committed under `runs/run-<N>/<target>/`:

- `<variant>.md` — the `result` field, the raw final message, unedited
- `<variant>.json` — the full `--output-format json` envelope: usage, cost,
  duration, model ids, number of turns
- `<variant>.meta.json` — harness record: CLI version, app SHA, prompt,
  wall-clock seconds

App sources, recorded at bundling time:

| Bundle | Repo | Branch | SHA |
|---|---|---|---|
| `pcs.bundle` | postcraftstudio | main | `63f4ff5698a9459f17e03663aaa9349b4b27b51b` |
| `srb.bundle` | short-ruby-bookmarks | main | `9535f1eb2d9460a1766c5060383e6cb1585c749b` |

Both target files are byte-identical between these SHAs and the branches the
earlier experiment read from.

The scripts are [`scripts/run_grid.rb`](scripts/run_grid.rb) (host, resumable,
one container per cell) and [`scripts/trial.rb`](scripts/trial.rb) (inside the
container).
