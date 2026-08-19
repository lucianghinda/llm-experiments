# statusline-per-project

**Question:** can a Claude Code status line be set per project, so different
folders show different bars, and can that setting be committed and shared?

**Answer:** yes to both. The second half is the interesting part, because the
obvious reading of the docs says no.

Measured on Claude Code `2.1.234`, two real interactive sessions.

## Result

| Claim | Method | Result |
|---|---|---|
| A project `.claude/settings.json` overrides the global `statusLine` | opened a session in each folder | **confirmed**, the project bar drew and the global bar did not |
| `claude -p` runs the status line | ran `claude -p` with a capture probe | **no**, the probe never fired, so a headless run cannot test a bar |
| `"command": "./.claude/statusline.rb"` (relative) | marker probe at a relative path | **resolves**, `Dir.pwd` is the project directory |
| `"command": "ruby \"$CLAUDE_PROJECT_DIR/...\""` | marker probe behind the variable | **resolves**, the variable is set to the project directory |
| `padding: 2` indents the bar | compared rendered output | **confirmed**, two leading spaces on `docs-site` |
| `COLUMNS` and `LINES` are set | read from the probe environment | **not seen**, both were nil, see caveats |

The two bars, captured from the real sessions:

    api-service │ Opus 5 (1M context) · api-service · experiment/statusline-per-project*

    docs-site   │   docs-site | Opus 5 (1M context) | xhigh effort | default
                │ ░░░░░░░░░░░░░░░░ 0% ctx 0/1M 0:01

## Why the portable form matters

A status line command runs through a shell, so the natural assumption is that
it needs an absolute path. That would make a project level `statusLine`
unshareable, because a committed `settings.json` would carry one machine's home
directory into everyone else's checkout.

Measuring it says otherwise. Claude Code runs the command with the working
directory set to the project directory **and** exports `$CLAUDE_PROJECT_DIR`.
So this is committable as is, with no absolute path anywhere:

```json
{
  "statusLine": {
    "type": "command",
    "command": "ruby \"$CLAUDE_PROJECT_DIR/.claude/statusline.rb\""
  }
}
```

Both projects here use exactly that. `$CLAUDE_PROJECT_DIR` is preferred over the
relative form because `workspace.current_dir` can move during a session while
`workspace.project_dir` does not, so a relative path has a failure mode the
variable does not.

Worth flagging: the status line docs never mention `$CLAUDE_PROJECT_DIR`. They
document it for hooks only. This result is observed behaviour, not a promise,
so it could change.

## What the payload really looks like

Full captures in [`results-raw/`](results-raw/), paths and session ids redacted.
Differences from what the docs example led me to expect:

- `used_percentage`, `remaining_percentage` and `current_usage` are all `null`
  at session start, not `0`. A bar that does arithmetic on them straight away
  gets a `NoMethodError`, which is why both scripts fall back to computing the
  percentage themselves.
- `model.display_name` is `"Opus 5 (1M context)"`, not a short `"Opus"`. Long
  enough to change how a bar is laid out.
- `workspace.git_worktree` and `workspace.repo` are populated here, because
  this experiment lives in a linked worktree.
- Absent in these captures: `session_name`, `prompt_id`, `pr`, `agent`,
  `worktree`, `rate_limits`. Do not assume any field exists.

## Harness

`capture-payload.rb` writes the raw payload plus the environment to
`results-raw/`, then delegates to the project's own status line so the session
still looks normal. Point a project's `settings.json` at it:

    "command": "<experiment-root>/capture-payload.rb <project-folder>"

Sessions were driven non-interactively under a pty, because the bar does not
render under `claude -p`:

    cd api-service && timeout 40 script -q /dev/null claude </dev/null

## Running the bars without a session

The contract is stdin in, stdout out, and nothing goes back to the model, so a
pipe is enough to iterate on a bar:

    echo '{"model":{"display_name":"Opus 5 (1M context)"},
           "workspace":{"current_dir":"'"$PWD"'"},
           "output_style":{"name":"default"},
           "effort":{"level":"xhigh"},
           "cost":{"total_cost_usd":0.0731,"total_duration_ms":252000,
                   "total_lines_added":156,"total_lines_removed":23},
           "context_window":{"total_input_tokens":312450,
                             "context_window_size":1000000,
                             "used_percentage":31}}' \
      | ./.claude/statusline.rb

## Caveats

- `COLUMNS` and `LINES` came back nil, though the docs say they carry the
  terminal size from v2.1.153 and this ran on 2.1.234. The sessions were driven
  under `script -q /dev/null` with stdin closed, so this is more likely an
  artefact of the harness than a real gap. Untested in a human driven terminal.
- Both sessions were empty. Every cost field was zero and the context window was
  zero, so the coloured thresholds in the bars were never exercised with real
  numbers.
- Two runs, one machine, one Claude Code version, macOS only.
- A custom status line suppresses most footer keyboard hints, including
  `esc to interrupt` and `? for shortcuts`. That is a real cost of running one.
- `api-service` shells out to `git` twice per render. Cheap locally, slow on a
  network mount, and Claude Code cancels a command that runs long.

## Docs

- <https://code.claude.com/docs/en/statusline>
- <https://code.claude.com/docs/en/settings>
