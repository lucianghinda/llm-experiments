# statusline-per-project

**Question:** can a Claude Code status line be set per project, so different
folders show different bars?

**Answer:** yes. `statusLine` is a normal top level key in `settings.json`, so
it follows the same precedence chain as every other setting:

    managed  >  command line  >  .claude/settings.local.json
             >  .claude/settings.json  >  ~/.claude/settings.json

A global bar in `~/.claude/settings.json` is the lowest layer. Any project that
ships its own `.claude/settings.json` with a `statusLine` key wins inside that
folder. The [status line docs](https://code.claude.com/docs/en/statusline) say
it directly: add the field to your user settings "or project settings".

This is a demonstration, not a measurement. There are no runs and no numbers.

## What is here

Two throwaway projects, each with its own bar, so the difference is visible
rather than asserted.

| Folder | Shape | Payload fields it reads |
|---|---|---|
| [`api-service/`](api-service/) | one line, git flavoured | `model.display_name`, `workspace.current_dir`, `cost.total_lines_added`, `cost.total_lines_removed`, `cost.total_cost_usd` |
| [`docs-site/`](docs-site/) | two lines, context meter | `model.display_name`, `output_style.name`, `effort.level`, `context_window.*`, `cost.total_duration_ms` |

Rendered from the same payload:

    api-service │ Opus · api-service · experiment/statusline-per-project* · +156/-23 · $0.0731

    docs-site   │ docs-site | Opus | high effort | explanatory
                │ █████░░░░░░░░░░░ 31% ctx 312.4k/1M 4:12

## Running it

    ruby setup.rb

`setup.rb` writes each `.claude/settings.json` from the committed
`.example` file, expanding `<experiment-root>` into the absolute path on this
machine. Then open either folder and trust it when asked:

    cd api-service && claude
    cd docs-site   && claude

`statusLine` runs a shell command, so it sits behind the same workspace trust
gate as hooks.

## Running a bar without starting Claude Code

The contract is stdin in, stdout out, so a pipe is enough. Nothing goes back to
the model, the status line is display only.

    echo '{"model":{"display_name":"Opus"},
           "workspace":{"current_dir":"'"$PWD"'"},
           "output_style":{"name":"explanatory"},
           "effort":{"level":"high"},
           "cost":{"total_cost_usd":0.0731,"total_duration_ms":252000,
                   "total_lines_added":156,"total_lines_removed":23},
           "context_window":{"total_input_tokens":312450,
                             "context_window_size":1000000,
                             "used_percentage":31}}' \
      | ./.claude/statusline.rb

## The absolute path problem

This is the part worth knowing before you commit a project status line.

The `command` value is run through a shell whose working directory you do not
control, so an absolute path is the only form I can show working. That fights
with sharing: a committed `.claude/settings.json` carries one machine's paths
into everyone else's checkout.

Three ways around it, only one of them verified:

| Form | Status |
|---|---|
| `"/abs/path/statusline.rb"` | verified, and what `setup.rb` generates |
| `"./.claude/statusline.rb"` | not verified, depends on the working directory the command inherits |
| `"ruby \"$CLAUDE_PROJECT_DIR/.claude/statusline.rb\""` | not verified, the docs promise this variable for hooks but never mention it for `statusLine` |

So this repo commits `settings.json.example` with an `<experiment-root>`
placeholder and generates the real file, the same shape as
`at-file-mentions/apps.local.example`.

Testing the two unverified forms needs a live interactive session, because the
status line does not render under `claude -p`. That is the obvious next step
if this becomes a real experiment.

## Caveats

- Both scripts are `chmod +x` with a `#!/usr/bin/env ruby` shebang, so
  `command` points straight at the `.rb` file. Without the executable bit the
  setting has to become `"command": "ruby /abs/path/statusline.rb"`.
- Both parse stdin inside a `rescue` and fall back to `Dir.pwd`. A status line
  that raises gives you a broken bar on every single turn, so swallowing the
  error is the right trade here. Tested with empty stdin.
- `api-service` shells out to `git` twice per render. That is cheap locally and
  slow on a network mount, and Claude Code cancels a command that runs long.
- `padding` is a knob that exists only on `statusLine`, not on hooks. It is
  relative indentation on top of the built in spacing, not distance from the
  terminal edge. `docs-site` sets it to 2.
- The branch `api-service` shows is this repo's branch, because the folder
  lives inside the worktree. Both demo projects report the same branch here.
  Outside a repo the segment falls back to `no-git`.

## Docs

- <https://code.claude.com/docs/en/statusline>
- <https://code.claude.com/docs/en/settings>
