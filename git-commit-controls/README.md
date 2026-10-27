# Experiment: which settings actually change a git commit message?

Three coding agents write commit messages, and each ships a different pile of
knobs that claim to control them: attribution settings, instruction files, agent
hooks, git hooks. This experiment asks a narrow question about all of them:

> Which of these knobs change the bytes that end up in `git log`?

Every trial gives an agent the same repository, the same staged change and the
same four-word prompt, varies exactly one control, and keeps the commit message.

**240 trials: 104 on the host, then 136 in a clean room.** The clean-room run is
the one the conclusions rest on. The host run is kept because the difference
between the two is itself a result.

## Why the question needs an experiment

The documentation for these settings describes them in the language of
post-processing: attribution is *appended*, *replaced* or *removed*. That wording
implies the harness edits the message after the model writes it, which would make
every setting deterministic.

The measurements below show that is mostly not how it works. Most of these knobs
are **prompt edits**: they change what the model is asked to do, and the model
complies at some rate below 100%. A small number are **mechanisms**: they edit
the bytes whatever the model wanted. Telling the two apart is the point, and it
is not something a settings reference will tell you.

## The design

`scripts/fixture.rb` builds a throwaway repo for every trial: three commits of
deliberately plain, non-conventional history, and one staged bug fix where
`Cart#total_cents` ignored `quantity`. The prompt is the same everywhere:

```
Commit the staged change.
```

The prompt names no convention and no attribution policy, so anything that shows
up came from the arm, from the agent's defaults, or from the model imitating the
log. The history is non-conventional on purpose: a `fix(cart): ...` subject
cannot be explained by imitation, so it is evidence about the control.

After the agent finishes, the runner keeps `git log -1 --pretty=%B` and deletes
the repo. The whole experiment's raw output is under a megabyte.

### What is measured

`scripts/measure.rb` scores every message: whether an attribution trailer is
present and its exact text, whether the subject matches Conventional Commits,
body length, subject length, and whether the message mentions AI at all.
`scripts/report.rb` turns those into per-arm rates. `scripts/compare.rb` puts the
two runs side by side. `scripts/verify.rb` re-checks that the fixture is
reproducible, that every trial committed, that no arm's settings drifted from the
table, and that no arm mixed toolchains.

### Replicates

The first pass ran two replicates per cell and produced a result that could not
be read: the `Co-Authored-By` trailer appeared in 1 of 20 runs. An arm scoring
zero proves nothing when the baseline is near zero either.

So the attribution family runs at higher replicate counts, to estimate a rate
rather than a yes/no. Cells testing a deterministic mechanism stay at n=2,
because a mechanism that fires twice out of two is not what needs statistics.

## The two runs

| | host run | clean room |
|---|---|---|
| trials | 104 | 136 |
| Claude config | the machine's own `~/.claude` — `CLAUDE.md`, `settings.json`, hooks | none exists |
| Codex config | isolated `CODEX_HOME` (auth only) | same, plus a clean environment |
| opencode config | isolated `XDG_CONFIG_HOME`, `HOME` moved | none exists |
| environment | the full host shell environment | container's own |
| CLI | resolved past a cmux wrapper shim | mounted, pinned |

The clean room runs one fresh Apple container per trial, using the repo's
[`containers/`](../containers/) kit. See
[`container/README.md`](container/README.md) for how it works, why no image was
built, and the refresh-token trap that broke the first attempt.

## Results

Rates below are from the clean room unless a row says otherwise. Full tables:
[`RESULTS-container.md`](RESULTS-container.md), host in
[`RESULTS.md`](RESULTS.md), both side by side in
[`COMPARISON.md`](COMPARISON.md). `ruby scripts/verify.rb` passes on both sets.

### 1. Almost none of these knobs are deterministic

| Evidence | Reading |
|---|---|
| Claude default attribution, Sonnet: **6/16** | the trailer is not appended by the harness |
| Same settings on Opus: **8/8** | compliance is a property of the *model* |
| `attribution.commit` set to a custom literal: **4/8** carried it | the value is a template the model is asked to echo |

If attribution were post-processing, the custom string would appear 8 times out of
8. It appeared 4 times, and what came out was the arm's own text,
`Co-Authored-By: Robot <robot@example.com>`. So `attribution.commit` is a
**template injected into the prompt**, and whether it reaches `git log` depends on
the model deciding to write it. The same configuration therefore produces
different commits on different models.

### 2. The attribution switches work, and the deprecated one still works

Read against `control-cli-263`, which is the same CLI build, at 6/16 (38%):

| Setting | attribution | vs baseline |
|---|---|---|
| control (2.1.263) | 6/16 | — |
| `attribution.commit: ""` | **0/8** | p ≈ 0.02 |
| `includeGitInstructions: false` | **0/8** | p ≈ 0.02 |
| `includeCoAuthoredBy: false` (deprecated, on 2.1.258) | **0/8** | vs its own 3/16 baseline |

Pooling the clean room with the host run, every attribution-off arm is 0/16
against a pooled control rate of 14/32. Two of those rows carry a consequence
beyond the number:

- The deprecated `includeCoAuthoredBy: false` is still fully effective.
  The docs say to use `attribution` instead; they do not say the old key stopped
  working, and it has not.
- `includeGitInstructions: false` **also removes attribution**, which is not what
  its description says it does. The instruction to add the trailer lives *inside*
  the built-in git instructions, so turning those off takes the trailer with it.

### 3. The default trailer names the model, and there is no session trailer

Every trailer observed, verbatim:

```
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

It carries the model name, not a generic `Claude`. With
`attribution.sessionUrl: true` explicitly set, a local `-p` run produced no
`Claude-Session:` trailer at all. That trailer belongs to hosted sessions, so
switching it off on a laptop turns off something that was never on.

### 4. Only the hook layers are mechanisms

| Control | Claude | Codex | opencode |
|---|---|---|---|
| git `prepare-commit-msg` hook | 2/2 | 2/2 | 2/2 |
| agent `PreToolUse` hook | 2/2 | 2/2 | n/a |

The git hook forced a Conventional Commits subject in 6 of 6 trials across all
three agents. It runs after the model is finished and does not care what the model
wanted; it also strips attribution by construction.

The agent-level `PreToolUse` hook rewrites the *command* rather than the message.
It reached 2/2 in the clean room for both agents that have it, and on Codex it
left a visible fingerprint. The forced prefix landed in the body as well:

```
fix(cart): Include quantities in total

fix(cart): Cart totals previously counted each line item only once, regardless of
quantity. Include every unit when calculating the total in cents.
```

That is the weaker of the two guarantees: it depends on the shape of the command
the model happens to write, and this hook only rewrote a `-m "..."` form. On the
host it reshaped 1 of 2; the other commit carried no prefix. The harness never
logged the command, so whether the hook failed to fire or failed to match is not
recorded.

### 5. All three agents default to plain, non-conventional subjects

With no configuration at all, on identical input:

| | Conventional subject | body | attribution |
|---|---|---|---|
| Claude Code (Sonnet, 2.1.263) | 0/16 | 2/16 | 6/16 |
| Codex | 0/8 | 0/8 | 0/8 |
| opencode | 0/8 | 0/8 | 0/8 |

All three imitate the plain history they can see. This corrects the host run,
where Codex appeared to write Conventional Commits with a body 8/8 by default.
That was an artifact of the host environment, not a property of Codex. See
[§7](#7-what-isolation-changed).

Codex added **no attribution in 22 of 22 trials**, despite shipping a
`<git_attribution>` prompt block asking it to end commit messages with
`Co-authored-by: Codex <noreply@openai.com>`. opencode added none in 16 of 16,
consistent with having no attribution code at all.

### 6. Instruction files: what carries

Every one of these moves its agent from a plain default to Conventional Commits
with a body:

| Mechanism | Result |
|---|---|
| Claude `CLAUDE.md` (project) | 2/2 |
| Codex `AGENTS.md` | 2/2 |
| Codex `AGENTS.override.md`, against a conflicting `AGENTS.md` | 2/2 — the override wins |
| Codex `developer_instructions` | 2/2 |
| Codex `model_instructions_file` | 2/2 |
| opencode `AGENTS.md` | 2/2 |
| **opencode `CLAUDE.md`** | **2/2** — opencode reads Claude Code's memory file |

A decoy instruction file asking for the *opposite* (plain one-line subject, no
body) holds both agents at 0/2, but that arm does not discriminate in the clean
room: both agents already default to a plain subject, so the decoy asks for what
they do anyway. It separated instruction from default in exactly one cell, host
Codex, where the contaminated default was conventional and the decoy pulled it
to 0/2. The clean-room evidence rests on the positive direction only.

The opencode row needs a warning: opencode falls back to `CLAUDE.md`, project
and global, unless `OPENCODE_DISABLE_CLAUDE_CODE=1` is set.

### 7. What isolation changed

Re-running in a clean room changed exactly one conclusion, and it is a big one.

**Codex's default commit style was a host artifact.** Host 8/8 Conventional
Commits with a body; clean room 0/8, plain. Same Codex build, same `auth.json`,
same prompt, same fixture, same isolated `CODEX_HOME` with no `config.toml`. The
difference is the environment: Codex inherits the host shell environment by
default, and re-running it *on the host* under `env -i` reproduced the clean-room
result in 2 of 2.

The knock-on: on the host, `AGENTS.md`, `developer_instructions` and
`model_instructions_file` all looked like no-ops, because Codex's apparent
default already produced what they asked for. In the clean room each one moves
Codex from 0/8 to 2/2. **Isolation is what made Codex's instruction channels
measurable at all.**

**Claude Code's conclusions did not change.** The clean room's attribution rate
looked far lower at first (3/16 against the host's 8/16), but that gap is mostly
CLI version, not host configuration: the clean room's default build is 2.1.258
and the host ran 2.1.263. The `control-cli-263` arm, identical except for the
build, gives 6/16, statistically indistinguishable from the host's 8/16. `control-opus`
reproduces the host exactly at 8/8. A five-patch CLI difference moved the
attribution rate about as much as the entire host configuration did, which is its
own small lesson about pinning versions.

**opencode's conclusions did not change** in any arm.

## Scorecard against the claims this experiment started from

| Claim | Verdict |
|---|---|
| `attribution.commit: ""` removes the trailer | **Holds** (0/8), but it is a prompt template, not an append/replace step |
| `attribution` is a "Direct" control, unlike the "indirect" prompt-level ones | **Wrong in kind.** Exactly as indirect as `CLAUDE.md`: 4/8 compliance on a custom value |
| `includeCoAuthoredBy` is superseded | **Still works** (0/8) |
| `includeGitInstructions: false` removes built-in commit/PR instructions | **Holds**, and additionally removes attribution — an undocumented coupling |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` is the env equivalent | **Not verified.** Not in the environment-variable reference; not tested here |
| `attribution.sessionUrl` matters for commit bytes | **Not locally.** No session trailer appeared even with it `true` |
| Codex has "no documented equivalent" for commit attribution | **Wrong.** Codex ships a `<git_attribution>` prompt block. It produced nothing in 22/22 trials, so the *outcome* matches, the *mechanism* does not |
| Codex `developer_instructions`, `model_instructions_file`, `project_doc_*` exist | **Hold.** All four are real keys in 0.153.4 |
| Codex `git_commit_instructions` / `desktop.git-commit-instructions` | **Absent** from the 0.153.4 CLI binary. A Desktop-only setting is neither confirmed nor denied here |
| `AGENTS.override.md` is real and outranks `AGENTS.md` | **Holds** (2/2 against a conflicting `AGENTS.md`) |
| Codex `PreToolUse` can rewrite a command | **Holds** (2/2), needs `permissionDecision: "allow"` alongside `updatedInput` |
| opencode plugin hook `shell.create.before` | **Does not exist** in 1.18.15. The shell hook is `shell.env`; `tool.execute.before` is the one to use |
| opencode no longer falls back to `CLAUDE.md` | **Wrong.** It reads project and global `CLAUDE.md` (and `CONTEXT.md`) unless `OPENCODE_DISABLE_CLAUDE_CODE=1` |
| opencode has no attribution setting | **Holds** — no attribution code at all; 0/16 |
| Git hooks are the last and strongest layer | **Holds**, and the only layer that behaved deterministically: 6/6 |

### The practical shape of the answer

Ranked by how reliably a control reaches `git log`:

1. **`prepare-commit-msg` / `commit-msg` git hooks** — deterministic, agent-agnostic, 6/6.
2. **Agent `PreToolUse` hooks** — deterministic in principle, brittle in practice, because they rewrite a *command string* whose shape the model chooses.
3. **Instruction files and settings** — high compliance on style, variable on exact literals, model-dependent, and in Codex's case sensitive to the ambient environment.

If a commit convention has to hold, it belongs in a git hook. Everything
above that line is a request.

## Caveats

- **One task, one repository, one language.** A single staged Ruby bug fix with an
  obvious reason. Rates on a murkier change may differ.
- **The clean room's Claude is 2.1.258**, five patches behind the host's 2.1.263,
  except for the three arms that pin 2.1.263 explicitly. Given that this version
  gap moved the attribution rate from 3/16 to 6/16, arms measured only on 2.1.258
  should be read as that build's behaviour.
- **Cross-agent numbers are not a model comparison.** Claude ran on Sonnet (and
  Opus in one arm), Codex on its default, opencode on
  `openai/gpt-5.3-codex-spark` because no Anthropic model is currently selectable
  in this opencode install. Differences between agents mix harness and model.
- **Thin cells.** Arms testing a deterministic mechanism use n=2 deliberately; only
  the attribution family has enough replicates for a rate. `sessionurl-true` at n=2
  supports only the weak claim made for it.
- **Two workarounds are required for any trial to run.** Codex's `workspace-write` sandbox refuses
  to write `.git/index.lock`, so every Codex trial names the repo's `.git` in
  `sandbox_workspace_write.writable_roots`; without it no Codex trial can commit.
  opencode does not inherit the spawn working directory and must be given `--dir`,
  or it operates on whatever directory it resolves for itself.
- **The Codex environment finding is not fully diagnosed.** It is established that
  a scrubbed environment reproduces the clean-room result; *which* variable does it
  is not identified.
- **The harness records less than it should.** It checks that `HEAD` moved, not
  that exactly one commit was created containing only the staged change, and it
  never logs the command each agent ran. `PRETOOLUSE_HOOK` accepts a
  `GCC_HOOK_LOG` path for exactly that and no runner sets it, which is why the
  one host hook miss has no explanation. Repos are deleted after each trial, so
  this cannot be recovered from the existing runs.
- **The decoy arm does not discriminate in the clean room.** It was meant to show
  an instruction file steering away from the default as well as toward it, but
  both Codex and opencode already default to a plain subject, so asking for a
  plain subject proves nothing. It worked in one cell only: host Codex.

## Reproducing

Host run:

```sh
export GCC_WORK=/tmp/gcc
ruby scripts/runner.rb claude 16 control
ruby scripts/runner.rb codex 2
ruby scripts/runner.rb opencode 2
ruby scripts/measure.rb && ruby scripts/report.rb && ruby scripts/verify.rb
```

Clean room (see [`container/README.md`](container/README.md)):

```sh
export GCC_WORK=/tmp/gccc
ruby scripts/container_runner.rb claude 16 control
GCC_RUNS=runs-container ruby scripts/measure.rb
GCC_RUNS=runs-container ruby scripts/report.rb
GCC_RUNS=runs-container ruby scripts/verify.rb
ruby scripts/compare.rb
```

Each throwaway repo is deleted once its commit message has been read, so the
experiment costs well under a megabyte rather than a container image per trial.
