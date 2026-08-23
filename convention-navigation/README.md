# Does Rails convention-over-configuration save an agent tokens?

**Status: harness built, scramble verified, pilot not yet run.**

The two layouts are built and proven equivalent — same code, same gems, same
routes, same 348 passing tests — and a trial runs end to end from prompt to
scripted verdict. All four acceptance checks have been exercised against real
agent runs. What has not happened is the grid.

**Nothing below is a result.** The numbers quoted from validation trials are
n=1, were run to prove the harness works rather than to answer the question, and
are not published in `results/`. They stay in the gitignored `results-raw/`.

## The question

The assumption under test: an agent working on a conventional Rails app already
knows where things live, so it searches less, reads less, and spends fewer
tokens than it would on an app whose author put things wherever they liked and
wired them together with configuration.

The counter-hypothesis is just as plausible and is stated first on purpose:
**grep does not care where a file lives.** An agent that searches by identifier
finds `def create_bot!` in one call whether the file is `app/models/user/bot.rb`
or `platform/core/entities/user/bot.rb`. If agents navigate by search rather
than by prediction, the layout is nearly free and the assumption is wrong.

That is not a theoretical worry. `at-file-mentions` already watched it happen: a
trial given no path reached the defect file on tool call 1 with
`find . -name "*private_network*"`. And the very first trial run through this
harness went `rg` first, then read the file — a search, not a prediction.

Either outcome is a finding. The design exists to tell them apart.

## The design

**One app. Same code. Two layouts.** Comparing a Rails app against some Express
or FastAPI app would measure language, size, feature set and training-data
familiarity all at once, and none of the difference could be attributed to
conventions. So the comparison is campfire against a rearranged campfire:

| Condition | Layout |
|---|---|
| `conventional` | the app as its authors wrote it |
| `scrambled` | the same code, non-conventional layout, wired through configuration |
| `scrambled-mapped` | `scrambled` plus a file documenting where everything is |

`conventional` vs `scrambled` isolates what convention knowledge is worth.
`scrambled-mapped` asks the practical follow-up: if your architecture is
nonstandard, does writing it down buy the advantage back — and what does
carrying that document cost on every request? Its tokens are charged, not
hidden.

### The scramble

```
app/models       -> platform/core/entities
app/controllers  -> delivery/http/handlers
app/helpers      -> delivery/http/render_support
app/views        -> delivery/http/render
app/jobs         -> platform/async/workers
app/channels     -> delivery/sockets
db/migrate       -> db/changes
config/routes.rb -> a loader over six files in config/routing/
test/models      -> test/suite/persistence      (and five more buckets)
```

Two top-level roots at unequal depths, not one. A scramble that put everything
under a single new parent would be learnable in one `ls` and would measure
almost nothing; real config-heavy codebases are inconsistent, and that
inconsistency is the treatment rather than noise.

**Files move. Code does not.** No class, module, method or constant is renamed
anywhere, and no file's contents change except eight wiring files. That is what
makes a difference attributable to path knowledge: grep-by-identifier is exactly
as powerful on both sides, so anything the agent loses is prediction.

**Whole roots move, never anything below them.** Under Zeitwerk every directory
below an autoload root is a namespace — `app/models/room/` is not decoration, it
is `Room::`. Renaming one would rename a constant.

### What proves the two variants are the same application

`scramble_check.rb`, and nothing else. The whole design rests on one claim that
is easy to break by accident and impossible to check by eye across 720 files.
Current output:

```
ok  content: 720 file(s) identical after applying the manifest
ok  identifiers: 708 distinct name(s), same counts on both variants
ok  autoload roots: all 8 present in the scrambled tree
ok  gems: Gemfile and Gemfile.lock identical on both variants
ok  conventional: bin/rails zeitwerk:check
ok  conventional: bin/rails test (348 runs, 1011 assertions, 0 failures, 0 errors, 2 skips)
ok  scrambled:    bin/rails zeitwerk:check
ok  scrambled:    bin/rails test (348 runs, 1011 assertions, 0 failures, 0 errors, 2 skips)
ok  routes: identical on both variants (179 vs 179 line(s))
```

The identifier count is the one that guarantees the comparison is about paths
rather than searchability. `zeitwerk:check` is the one that catches a `concerns/`
directory left unregistered — which does not fail loudly, it just moves every
constant inside it under `Concerns::` and surfaces later as an unrelated
`NameError`.

### The tasks

Four for the pilot, in three families, with one prompt each. **The prompt is the
constant and the layout is the variable**, so every condition gets the same
words.

| Task | Family | What it asks |
|---|---|---|
| `locate-direct-type` | locate | where one rule is enforced; answer `path:line` |
| `locate-generated-secret` | locate | a value two levels deep in a namespace, and where it is set |
| `feature-room-topic` | cross-layer | add a field: migration, model, validation, controller, view |
| `test-direct-type` | test | write a test for a rule, and put it where tests belong |

`feature-room-topic` is the load-bearing one. A single lookup is where grep
wins; knowing *all* the places one field change lands is where convention
knowledge should show if it shows anywhere. Its migration is part of the test
rather than incidental to it: the scrambled variant reads migrations from
`db/changes`, so one written into `db/migrate` is never applied and the column
never appears.

Success is decided by script, never by eye. `test-direct-type` is not satisfied
by "a test file appeared and it is green" — a test that asserts nothing is green
too. The check mutates the rule out of the source, in both the places it is
enforced, and requires the agent's test to go red.

### What a prompt may not contain

No file path, no name of a directory belonging to either layout, and no word
that greps to three or fewer files **when one of them is a file this task's
answer lives in**. `render_prompts.rb` enforces this and refuses to render
otherwise.

Ordinary domain words are allowed and are meant to be there. "room" occurs in a
hundred files, locates nothing, and is what a real person would say. The
threshold does the work, not a banned-word list.

### Runs, and the decision rule, pre-registered

Phase 1: 4 tasks × 2 conditions × 2 agents × **5 repeats = 80 trials**. Five, not
three — this repository has already retracted claims built on three runs, and
the same prompt on the same tree can take four tool calls or fourteen.

Fixed before any trial runs:

- Within one agent, the assumption is **supported** if `scrambled` costs more
  than `conventional` in the same direction across tasks (sign test over tasks),
  **and** the search counts move the same way. Two agents agreeing strengthens
  it; one agent alone is reported as one agent alone.
- Per-task comparisons use the exact Mann-Whitney (n=5 vs n=5, 252 enumerated
  permutations). Consistency across tasks is the claim; one task separating on
  its own is not.
- **Only successful trials count toward cost.** A condition that saves tokens by
  giving up early has not saved anything. Failure rates are reported separately,
  and a higher failure rate on `scrambled` supports the assumption more strongly
  than any token difference.
- If token totals split but search counts do not, or the reverse, that mismatch
  is the finding and is reported as one.

## What gets measured

Per trial: total input tokens, output tokens, wall time, tool calls split into
search / read / edit / bash, distinct files read, calls until the first read of
a needed file, calls until the first edit, and the scripted verdict.

The sharpest number is **zero-search navigation**: did the agent reach a file it
needed without a single grep, glob or find beforehand? That is what "the model
already knows where to look" means, phrased so a transcript can answer yes or
no, and it does not depend on token accounting at all. It is `nil`, never
`false`, when the agent never arrived — "went straight there" is not a claim you
can make about a trial that never got there.

Counts are never pooled across agents: Claude reports structured tool calls and
Codex reports shell commands, so an average over both measures nothing. Token
accounting differs too, and getting it wrong is the easiest way to publish a
wrong number — see `startup-context/README.md`, where reading Codex's
`input_tokens` as excluding cache split every measurement into two clusters 35%
apart.

## What the validation trials showed about the harness

Five Codex trials, run to prove the machinery works. Each taught something about
the design rather than about the question.

**The cross-layer task is doable on the scrambled layout.** Given only
behaviour, the agent found `db/changes/` for its migration, edited the model,
the controller and the form partial under their moved paths, updated three test
files, and left the suite green at 354 runs. Both the worry that the task was
impossible without the conventional layout and the worry that it was trivial
turned out to be wrong, which is what a usable task looks like.

**Agents answer the test task by appending, not by creating.** Told to put a
test "where tests belong", the agent added one to the existing `room_test.rb`
rather than making a new file — the most idiomatic answer a conventional Rails
app allows. The check had to learn to accept that, and then to isolate the added
test by name so the mutation is judged against the agent's work rather than
against the suite's own coverage of the same rule.

**Neither locate trial navigated without searching.** Both went `rg` first, then
read. That is one data point per condition and settles nothing, but it is the
counter-hypothesis showing up immediately, and it is why
`zero_search_navigation` is recorded at all.

## Things that would have quietly ruined this

Each of these cost real time, and each would have produced confident, wrong
numbers.

**Moving the system tests changed which tests exist.** `bin/rails test` skips
system tests through a hardcoded path glob, `test/{system,dummy,fixtures}/**/*`.
Moved to `test/suite/browser/` they stopped matching it, so the scrambled
variant tried to boot a browser the container does not have and the whole suite
died on load. Every regression check on the scrambled side would have failed for
a reason with nothing to do with layout. System tests now stay put.

**The prompt leaked the answer through a code comment.** campfire's `Room` model
contains the word "conversation", and the first draft of two prompts described
the rule in exactly that word — so `grep -i conversation` went straight to the
file the agent was supposed to go looking for, in both variants. Counting files
alone would not have caught it as anything special; tying the rule to the task's
targets did.

**The parser counted a search as a prediction.** Codex's event JSON carries the
command's *output*, so a `rg` that merely printed the target path looked like
the moment the agent reached the file. The first real trial scored "went
straight there with no search" when the transcript plainly showed a grep
followed by a read. The error flatters the scrambled condition, which is the
direction this experiment least affords to be wrong in. Target matching now uses
only what the agent asked for, never what came back.

**A refreshed OAuth token was thrown away every trial.** Each trial copies
credentials into a private directory so nothing leaks between runs. When the CLI
refreshed an expired access token it wrote the replacement into that copy, which
dies with the container — and because refresh tokens rotate, the first trial
spent the stored one and every later trial failed with "OAuth session expired
and could not be refreshed". One good result, then a dead grid.

**And writing the credential back is itself dangerous.** A CLI that fails to
authenticate does not leave the file alone: it rewrites it with the same keys and
empty values. Copying that back turns one dead trial into a destroyed login,
silently, because the result is still valid JSON and `claude auth status` still
answers `loggedIn: true`. The write-back now refuses any candidate that empties a
field which was populated. Found by doing it.

**The branch isolation never ran, and nothing said so.** Each trial deletes every
branch but the one under test, so the two layouts cannot be diffed against each
other — a diff that would hand over the entire scramble, and the fact that it
was deliberate. The branches were listed with
`git branch --format=%(refname:short)`, passed to Open3 as a string; the
parentheses make Open3 route it through `sh`, where `(` is a syntax error. The
list came back empty, nothing was deleted, and both `trial/v1` and `trial/v2`
sat in every container. `meta.json` faithfully recorded
`branches_visible_to_agent: []`, which reads as "the agent saw no branches" and
meant "the question failed to be asked".

This was inherited from `at-file-mentions`, whose 102 published trials ran the
same way. Re-scanning those transcripts found five history commands, all
`git log --oneline`, and no command anywhere that can compare two refs — so no
published result changes. Both runners now single-quote the format string and
**abort the trial** if anything other than the branch under test survives, because
the failure mode was that everything looked normal.

**A dry run created a results directory.** `run_grid.rb` treats a directory with
a `meta.json` as work already done, so inspecting the plan would have removed
cells from it. Nothing is written now until the trial is real.

**An API error is not a failed trial.** A trial can die before the agent gets a
turn. Scored as a failure it would drag down whichever condition happened to be
running when the API hiccuped — a bias with no relation to layout. Those cells
are marked aborted, excluded from the data, never published, and retried.

## Layout

```
convention-navigation/
  apps.yml            the subject app and its toolchain
  scramble.yml        the move rules, the autoload roots, the wiring whitelist
  tasks.yml           ground truth, prompt files, acceptance checks, targets
  prompts-src/        the prompts as written
  prompts/            generated by render_prompts.rb, after validation
  variants/campfire/
    scrambled/        the eight wiring files, the only content that differs
    map.md            the document that IS the scrambled-mapped condition
    manifest.json     generated: every old path -> new path
  checks/
    lib/acceptance.rb shared plumbing for the acceptance checks
    campfire/         one check per task; success is decided here, by script
  scripts/
    scramble.rb              conventional + scrambled branches in the app repo
    scramble_check.rb        proves the two variants differ in layout and nothing else
    check_runtime.rb         the in-container half of that proof
    build_variant_image.rb   one image holding both layouts, gems in a cached layer
    render_prompts.rb        validates prompts, then publishes them
    run_trial.rb             one task, one agent, one condition, one container
    runner.rb                the in-container half of a trial
    run_grid.rb              the grid: blocked by task, rotated, resumable
    parse_transcript.rb      transcript -> events.jsonl + metrics.json
    metrics.rb               medians, exact Mann-Whitney, the sign test
    sanitize.rb              the gate between results-raw/ and results/
  results-raw/        gitignored. Everything, unfiltered
  results/            committed. campfire is MIT, so its transcripts cross whole
```

## Running it

```sh
cp convention-navigation/apps.local.example convention-navigation/.apps.local
$EDITOR convention-navigation/.apps.local
set -a; . convention-navigation/.apps.local; set +a

ruby containers/scripts/build_base.rb                              # once
ruby containers/scripts/auth_setup.rb                              # once, interactive

ruby convention-navigation/scripts/scramble.rb --app campfire
ruby convention-navigation/scripts/build_variant_image.rb --app campfire
ruby convention-navigation/scripts/scramble_check.rb --app campfire   # must pass first
ruby convention-navigation/scripts/render_prompts.rb

ruby convention-navigation/scripts/run_grid.rb --dry-run
ruby convention-navigation/scripts/run_grid.rb

ruby convention-navigation/scripts/parse_transcript.rb --all
ruby convention-navigation/scripts/metrics.rb
ruby convention-navigation/scripts/sanitize.rb
```

`scramble_check.rb` is not optional. A scramble that fails it has changed the
application rather than its layout, and every number measured against it would
be measuring that change.

The app repository is only ever read. Every branch is local, prefixed
`exp/convention/`, and nothing is pushed, merged or turned into a pull request.

## Caveats

- **Artificial disorder.** A real legacy app's layout co-evolved with its code.
  This measures the cost of losing path predictability specifically, which is
  the mechanism the assumption names, and not the cost of genuinely bad
  architecture.
- **The scramble is conservative, so any effect is a lower bound.** File
  basenames are unchanged, `lib/` does not move, and system tests stay put. A
  harsher scramble would cost the agent more; this one only removes
  directory-level prediction.
- **campfire is public and probably memorised.** That cuts both ways —
  memorisation of the conventional layout is part of what the assumption claims
  agents have — but it means the pilot cannot distinguish "the model knows
  Rails" from "the model knows campfire". Phase 2 repeats the best tasks on a
  private app, which is what separates them.
- **Four tasks and five repeats is not much power.** The statistics are exact
  rather than approximate for that reason. Small samples still mean only large
  effects will be visible.
- **`bin/rails routes` and friends work identically in both variants.** Runtime
  introspection is a legitimate navigation strategy and stays allowed, counted
  under bash calls. If agents lean on it, "conventions do not matter because the
  framework will tell you anyway" is the finding.
- **Rails' own error messages name paths.** A missing-template error prints
  where it looked. Both variants get this equally, but it helps `scrambled`
  recover, which shrinks the effect.
- **No planted bugs yet.** The bug-fix family is the most realistic task type
  and is missing from the pilot. Four of the five campfire bugs already in
  `at-file-mentions/bugs.yml` live in files that move here, and the way in is to
  plant the bug on the conventional branch and then scramble that, so both
  variants carry an identical defect.
- **This needs disk.** The base image is about 10 GB and the app image another
  4–8 GB. See the disk note in [`../containers/README.md`](../containers/README.md).
