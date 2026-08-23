# Does writing `@path/to/file.rb` instead of `path/to/file.rb` change what an agent does?

**Status: 30 trials run, plus two probes. The question is answered.**

`claude -p` resolves a bare `@path` and attaches the file; a `:line` suffix
stops it; `codex exec` does not resolve `@` at all. See [`RESULTS.md`](RESULTS.md).

The first 18 trials used `@path:line` throughout and so measured nothing —
`scripts/probe_attachment.rb` is the positive control that would have caught
it, and should be run before any comparison between conditions is believed.


## The question

When you hand an agent the file it needs, you can write the path plainly:

```
Relevant files:
app/models/user.rb:42
```

or with the mention syntax the chat interfaces use:

```
Relevant files:
@app/models/user.rb:42
```

In an interactive session `@` means something: the client resolves it and
attaches the file. In headless mode — `claude -p`, `codex exec` — nobody has
told me whether it still does, or whether it is just three extra characters of
prose. If it attaches, the file's tokens arrive in the first request and cost
money before the agent has done anything. If it is inert, it costs nothing and
does nothing.

So: **does the `@` change behaviour and cost, and in which direction?**

This is not about test reporter formats. Whether Minitest or RSpec output should
carry paths is a separate question for a separate experiment.

## The design

Five conditions in two families. The prompts are identical except for one block:

| Condition | Hint block |
|---|---|
| `none` | one sentence of domain language: no path, no filename, no line |
| `bare` | `Relevant files:` then `path:line`, one per line |
| `at` | the same list with `@` before each path |
| `bare_noline` | `Relevant files:` then `path`, no line number |
| `at_noline` | the same list with `@` before each path |

**`at_noline` vs `bare_noline` is the comparison that exercises the feature.**
`@path` resolves in `claude -p` and the file arrives in the first request.

**`at` vs `bare` is the suffixed pair, and both sides are inert.** `@file.rb:22`
is not a path that exists, so the mention stays literal text. That is kept rather
than deleted because it answers a real question about the form people write after
reading a stack trace — and the answer is that it buys nothing.

`none` measures what handing over the defect path is worth at all.

Two identities are enforced at render time. Within a family, stripping the `@`
prefixes from the `at` condition must reproduce the `bare` one byte for byte.
Across families, stripping `:line` must reproduce the `_noline` one. So a
difference between families is attributable to the line number and nothing else.

### Check the manipulation before believing a comparison

```sh
ruby at-file-mentions/scripts/probe_attachment.rb --app campfire --agent claude
```

It asks the agent to name every method in a file while forbidding tool use. If
the file was attached the agent answers; if not it replies `CANNOT SEE FILE`.
This is the positive control the first 18 trials lacked — they compared two inert
prompt forms, ran green, and produced a confident and wrong conclusion.

### One thing every condition is told

The failing test file is named in all five prompts. It is the task anchor.
Without it the agent has to run a whole Rails suite before it can see the
problem, and that runtime would swamp the cost difference being measured.

So `none` does not mean "no file is ever mentioned". It means **the defect
location is not handed over**. That is the variable.

**That compromise is larger than it looks.** Rails mirrors a test path onto an
implementation path, so naming the test file often names the defect file too:

```
test/lib/restricted_http/private_network_guard_test.rb   given in every condition
     lib/restricted_http/private_network_guard.rb        one `find` away
```

Observed, not theorised: in the first cond-none trial the agent's opening move
was `find . -name "*private_network*"`, which returned the implementation file
before it had run the suite or read anything. It reached the defect file on
tool call 1, the same as cond-bare.

Two of the three bugs planted so far have this property — campfire-01 and
bookmarks-01 mirror, postcraftstudio-01 does not, because its test is
`base_controller_test.rb` while its defect is in `concerns/api_auth.rb`. So
cond-none is, for those two, closer to "the path is one command away" than to
"the path is withheld".

This does not touch the `bare` vs `at` comparison, where the path is spelled
out in both. It weakens the `none` baseline specifically. When the remaining
bugs are picked, prefer fix commits whose implementation file is not the test
file's mirror; that is a mechanical check `probe_candidates.rb` could make,
the same way it already checks that a patch still applies backwards.

### The tasks

Real bugs in three real Rails applications, planted by taking a genuine merged
fix commit, applying its implementation diff backwards, and keeping its
regression test. The failing test is the one the maintainer actually wrote for
that defect.

| App | Privacy | Ruby | Database |
|---|---|---|---|
| once-campfire | public, MIT | 3.4.5 | SQLite |
| postcraftstudio | private | 4.0.1 | SQLite |
| short-ruby-bookmarks | private | 4.0.1 | Postgres |

Agents: Claude Code (`claude -p`) and Codex CLI (`codex exec`), compared only
within themselves. They do not count tool calls the same way, so a number
averaged across them measures nothing.

Run so far: 1 bug × 3 apps × 5 conditions × 2 agents = **30 trials**.

Full grid: 5 bugs × 3 apps × 3 conditions × 2 agents = **90 trials**, driven by
`run_grid.rb`. The suffixed pair `bare`/`at` is not run. A `:line` suffix stops
the mention resolving, so both sides are inert, and the measured difference came
out at +2 tokens three times out of three. `render_prompts.rb` still renders all
five: its cross-family identity checks are what make a difference attributable
to the line number and nothing else, and rendering text costs nothing.

The grid is blocked by bug, because the comparison is within a bug: all of one
bug's cells run close together, so a slow patch of machine time lands on every
condition of that bug rather than on one of them. Within a block the condition
order rotates with the bug index, so no condition always runs first or last. It
is resumable — a cell that already has a `meta.json` is skipped — and sequential,
because two trials at once share the machine and contaminate `wall_seconds`.

Of the fifteen planted bugs, seven withhold the defect path from `cond-none` and
eight are mirrors, where dropping `test/` from the named test file lands on the
implementation file:

| App | Withhold the path | Mirrored |
|---|---|---|
| campfire | 2 | 3 |
| postcraftstudio | 4 | 1 |
| bookmarks | 1 | 4 |

bookmarks contributes just one, `bookmarks-01`; all four of its new bugs are
mirrors. That is not a choice but the state of its history — only three of its
nineteen plantable commits withhold the path, one is `bookmarks-01` itself and
the other two bundle an unrelated test change with the implementation change, so
reverting the implementation would leave the test green. `cond-none` is
therefore weakest on bookmarks and strongest on postcraftstudio, and its cells
should be read per app rather than pooled.

## What gets measured

Per trial: wall time, input/output/cache tokens, total tool calls, tool calls
until the defect file is first read, tool calls until the first edit, whether the
fix made the test pass, and whether the trial hit its timeout.

A trial **runs to completion** under a wall-clock timeout rather than being
killed at the first edit. Stopping at the first edit would measure the cost of
locating the defect but throw away whether the fix was any good, and a tool-call
cap can always be applied afterwards from the recorded event log, whereas a
killed trial cannot be un-killed. Both the first-defect-read index and the
first-edit index are recorded, so a "cost to locate" figure is still available
without destroying the rest.

The headline number is **context carried before the first tool call**. That is
where auto-attachment would show up: if `@` makes the CLI attach the file, the
first request is already fat and no read is needed to get the contents. If `@` is
inert, the first request looks like the bare one and the file arrives later
through a normal read. Those two shapes are distinguishable, which is why
per-turn token counts are kept and not just the totals.

**This metric works for Claude and not for Codex.** Claude's stream reports usage
per model request, so the first request's context is visible directly. Codex
reports usage once per *turn*, and a turn contains all of its tool calls, so
there is no "before the first tool call" figure to read. For Codex the same
effect can only appear in the totals, which is weaker evidence. `metrics.json`
leaves the field null for Codex rather than filling it with a number that does
not mean what the column says.

## Why it all runs in containers

A throwaway `claude -p "reply OK"` on my own Mac arrives carrying 8 MCP servers,
39 tools, an auto-memory directory, 5 fired hooks and roughly **48,000 tokens of
context before the task starts**. That is larger than any effect this experiment
is looking for, and it varies by machine and by week.

Every trial therefore runs in a fresh Apple container with freshly installed
agent CLIs and no host state. `parse_transcript.rb` fails loudly if a trial ever
reports an MCP server or a memory path, so a contaminated run cannot be mistaken
for a clean one. See [`../containers/README.md`](../containers/README.md).

## Things that would have quietly ruined this

Recorded because each cost real time to find and each would have produced
confident, wrong numbers.

**The commit history was the answer.** The planted commit's message said
"reintroduce the defect fixed in `<sha>`" and its diff was the fix, inverted. One
`git log -p` would have skipped the search entirely — and skipped it *unevenly*,
because an agent given no path is far likelier to go digging through history than
one handed the path outright. The shortcut would have helped exactly the
condition expected to be slowest. Trial branches are now single orphan commits
called "Import application source", the originals are garbage-collected, and the
runner deletes every branch except the one under test so `git diff trial/base`
cannot reveal it either.

**A patch that applies cleanly is not yet a bug.** Later code can cover the same
case independently and leave the test green. `plant_check.rb` runs the suite and
records the actual failure; `runner.rb` re-checks it at the start of every trial
and aborts rather than scoring an imaginary bug as an instant fix.

**Most fix commits cannot be planted at all.** Campfire's SSRF guard was
rewritten by five later commits, so the one-line fix originally chosen no longer
existed as a line to remove. Of the five commits picked for campfire by reading
history, only two were still plantable. `probe_candidates.rb` now tests this
mechanically instead of trusting a reading of the log.

**The fix commit's first added test is not necessarily the failing one.** The
campfire fix replaced one test with two; reverting it leaves the first passing
and the second failing. Prompt line numbers come from `plant_check.rb`'s observed
failure, not from the diff.

**The agent's config directory was shared between trials.** `CLAUDE_CONFIG_DIR`
pointed at the mounted credential store, and Claude Code reported its
auto-memory directory inside it — writable, host-persisted, identical for
every trial. Nothing had been written to it yet, but a single memory noting
where the defect lived would have been read by every later trial, and it would
have helped cond-none most, which is the condition expected to be slowest. The
same directory also carried per-project onboarding state, so the first trial
of a grid did not start where the rest did. Each trial now gets a private copy
seeded with credentials only.

**The branch isolation never ran, and nothing said so.** `runner.rb` deletes
every branch except the one under test, so `git diff trial/base` cannot reveal
the planted change. It listed those branches with
`git branch --format=%(refname:short)`, passed to Open3 as a string — and the
parentheses make Open3 route it through `sh`, where `(` is a syntax error. The
command failed, the list came back empty, nothing was deleted, and the trial
carried on looking completely normal. All 102 published trials ran with both
`trial/base` and their own bug branch present.

Found in 2026-08 while building `convention-navigation/`, which copied this
runner and inherited the bug. Every published transcript was then re-scanned:
five trials ran a history command, all `git log --oneline`, which reveals
nothing because flattening gave every commit the same message. **No trial ran
`git diff`, `git show`, `git branch` or anything else that can compare two
refs**, so no result changes. The guarantee was still false while it held, which
is the part worth recording — `meta.json` reported
`branches_visible_to_agent: []` on every trial, and an empty list read as "the
agent saw no branches" when it meant "the question failed to be asked". The
runner now single-quotes the format string and aborts the trial if more than the
branch under test survives.

**A hermeticity check that always fires teaches you to ignore it.** The
original guard flagged a trial if any memory path existed. The CLI always
reports one, so it fired on clean runs — and would have fired on all 90. It
now checks where the path points rather than whether it exists.

**`tool_calls_to_first_defect_read` silently could not be computed.** The
runner knew the implementation files but never wrote them to `meta.json`, so
the parser matched against an empty list and returned nil for every trial. A
metric that is broken and a metric that is legitimately null look identical in
the output, which is the worst way for a measurement to fail.

## Layout

```
apps.yml          the three apps: ruby, database, files to neutralise
bugs.yml          ground truth per bug, and the cond-none hint wording
planted.yml       generated: proof each bug fails, and where
PROMPTS.md        generated: the template and every rendered prompt
prompts/          generated: one file per bug per condition
results/          committed. Raw transcripts for campfire, measurements only
                  for the two private apps
results-raw/      gitignored. Everything, unfiltered
scripts/
  probe_candidates.rb  which fix commits can still be planted
  plant.rb             creates the base and bug branches
  plant_check.rb       proves each planted bug fails; writes planted.yml
  render_prompts.rb    bugs.yml -> prompts/ and PROMPTS.md
  run_trial.rb         runs one trial in a container
  runner.rb            the in-container half of a trial
  parse_transcript.rb  transcript -> events.jsonl + metrics.json
  sanitize.rb          the gate between results-raw/ and results/
  metrics.rb           medians and exact Mann-Whitney U
```

## Running it

```sh
cp at-file-mentions/apps.local.example at-file-mentions/.apps.local
$EDITOR at-file-mentions/.apps.local          # your checkout paths; gitignored
set -a; . at-file-mentions/.apps.local; set +a

# Worktrees live here. The default is under /tmp, which macOS cleans out; when
# that happens plant.rb rebuilds them, but the stale registrations it leaves in
# each app repo have to be dropped first, and `git worktree prune` is too blunt
# if the repo also has worktrees of your own.
export LLMX_PLANT_ROOT="$HOME/.llmx/plant"

ruby containers/scripts/build_base.rb
ruby containers/scripts/auth_setup.rb                    # once, interactive
ruby at-file-mentions/scripts/plant.rb
ruby containers/scripts/build_app_image.rb --app campfire
ruby at-file-mentions/scripts/plant_check.rb              # every bug must fail first
ruby at-file-mentions/scripts/render_prompts.rb

ruby at-file-mentions/scripts/run_smoke.rb --dry-run      # 4 trials, harness check
ruby at-file-mentions/scripts/run_grid.rb --dry-run       # 90 cells, the experiment
ruby at-file-mentions/scripts/run_grid.rb

ruby at-file-mentions/scripts/parse_transcript.rb --all
ruby at-file-mentions/scripts/metrics.rb
ruby at-file-mentions/scripts/sanitize.rb
```

The app repositories are only ever read. Every branch is local, prefixed
`exp/path-hints/`, and nothing is pushed, merged or turned into a pull request.

## Caveats

- **Five bugs per cell is not much power.** The statistics are exact rather than
  approximate for that reason: with n=5 against n=5 there are only 252 ways to
  split the data, so the p-values are enumerated rather than estimated. Small
  samples still mean only large effects will be visible.
- **Campfire is public**, so its code may be memorised. The defect path is handed
  over in two of three conditions anyway, which limits how much that matters, but
  it is a reason not to pool campfire with the private apps.
- **Codex and Claude report tool use differently.** Comparisons stay within an
  agent.
- **The trial repository has no real history.** Flattening was necessary to stop
  the answer leaking. All conditions are affected identically, so it does not
  bias the comparison, but it does make the checkout less realistic than a
  working repository.
- **`@` may turn out to be inert** in one or both headless CLIs. That is a
  finding, not a failure; the cost of the raw text is still measured.
- **This needs disk.** The base image is about 10 GB, each app image another
  4-8 GB, and the BuildKit cache reached 9.8 GB building a single Rails app.
  See the disk note in [`../containers/README.md`](../containers/README.md).
