# Results: does `@path/to/file.rb` change what an agent does?

Yes for Claude Code in both front ends, no for Codex in either, and a
line-number suffix breaks it.

102 trials — 15 bugs across 3 apps, 2 agents — plus two probes that answer the
mechanism directly. Every trial reproduced its planted bug before the agent
started, every fix was verified by the app's own test, and no agent edited
anything under `test/`.

The live comparison runs at 5 bugs per cell, which is enough to separate: the
context effect comes out at p = 0.0079 with **U = 0.0 in all three apps**, the
smallest p this test can return at n=5 and no overlap between the two groups
anywhere.

Run 2026-08-18. Claude Code 2.1.233 pinned to `claude-opus-5`; Codex CLI 0.147.0
pinned to `gpt-5.6-sol`. Fresh Apple containers, no MCP servers, no host state.
An earlier 30 trials ran with Codex unpinned; those transcripts carry no model
field, so they are not attributable to a version and are not pooled here.

## The answer

| prompt form | `claude -p` | Claude TUI | `codex exec` | Codex TUI |
|---|---|---|---|---|
| `@app/models/user.rb` pasted | **file attached** | **file attached** | not resolved | not resolved |
| `@app/models/user.rb` typed into the picker | n/a | untested | n/a | `@` stripped, path sent, not attached |
| `@app/models/user.rb:42` | not resolved | untested | not resolved | untested |
| `app/models/user.rb` | not resolved | untested | not resolved | untested |

Claude attaches the file. Codex never does: in its TUI the `@` is a filename
completer whose trigger character is consumed, so what reaches the model is a
plain path. This is a product difference, not a limitation of headless mode.

Three consequences worth knowing before you write another prompt:

- **`@path` in `claude -p` is not free.** The file's tokens arrive in the first
  request whether or not the agent ever needed them. Median +2,335 to +4,891
  tokens across three apps at 5 bugs each, scaling with file size, with no
  overlap between the mentioned and unmentioned groups in any app.
- **It buys presence, not less work.** Total tool calls, output tokens and wall
  time do not move (p ≥ 0.37 everywhere). At one bug per cell the first run
  hinted `@` bought fewer tool calls; at five it does not.
- **`@path:line` buys nothing anywhere.** The form that reads naturally after a
  stack trace costs one token per `@` and attaches nothing. If you want the
  agent to have the file, drop the line number from the mention.

## How it was established

Token accounting alone was not enough, so the mechanism was tested behaviourally
as well.

### The behavioural probe — `scripts/probe_attachment.rb`

Asks a question only the file's contents can answer, and forbids running
anything: *name every method defined in that file*. The needle is a private
method that appears nowhere else, so a correct answer cannot come from the path
or from memory of the repository.

| | prompt | tool calls | answer |
|---|---|---|---|
| **claude** | `@path` | 0 | `resolve, private_ip?, disallowed_ipv4?, disallowed_ipv6?, embedded_ipv4` |
| claude | `@path:line` | 0 | CANNOT SEE FILE |
| claude | `path` (control) | 0 | CANNOT SEE FILE |
| **codex** | `@path` | 0 | CANNOT SEE FILE |
| codex | `@path:line` | 0 | CANNOT SEE FILE |
| codex | `path` (control) | 0 | CANNOT SEE FILE |

Claude names all five methods without touching a tool. That is only possible if
the file was already in context.

### The token probe — `scripts/probe_mention.rb`

Quantifies the cost for Claude. First model request, campfire, implementation
file 2,867 bytes and test file 5,146:

| prompt form | first request | vs no mention |
|---|---|---|
| no file mentioned | 19,092 | — |
| `path` | 19,110 | +18 |
| **`@path`** | **20,716** | **+1,624** |
| `path:line` | 19,113 | +21 |
| `@path:line` | 19,114 | +22 |
| `@test @impl` | 23,451 | +4,359 |
| `@test:line @impl:line` | 19,140 | +48 |

Repeats give identical figures to the token.

**This probe does not work for Codex** and its Codex output should be ignored.
Codex reports usage once per turn, and two runs of the identical probe disagreed
on four of seven cases, moving by ~800 tokens — the same size as attaching a
small file. That is why the behavioural probe exists.

## The interactive clients

Both TUIs were driven by hand in the same container, on the same planted branch,
and their session files read back. `scripts/manual_trial.rb` opens them;
`scripts/parse_manual.rb` reads the result.

**Entry mode is part of the result.** Typing `@` and choosing from the client's
completion list is a different code path from pasting text that happens to
contain an `@`, and a client can implement one and not the other. Both were run
for Codex, and they differ in what reaches the model. Claude was run pasted
only.

### Claude TUI attaches pasted mentions

The session contains two records of `type: "attachment"`, each with
`attachment.type == "file"`:

```
/workspace/app/test/lib/restricted_http/private_network_guard_test.rb   5,620 bytes
/workspace/app/lib/restricted_http/private_network_guard.rb             3,138 bytes
```

Those are the two files the prompt named. The attachment is a **separate
record**, not a rewrite of the message — the stored user message is still the
397-character prompt with both `@` characters intact. Mention text and attached
file travel side by side, which is why "did the `@` survive in the message" is
useless as a test of whether anything was attached.

### Codex TUI does not attach pasted mentions

The stored prompt is the pasted text, `@` intact, with no file body. The file
contents first appear at record 13, and the path there is a tool call the agent
made itself. Its first tool call was:

```
sed -n '1,240p' test/lib/restricted_http/private_network_guard_test.rb && \
sed -n '1,240p' lib/restricted_http/private_network_guard.rb
```

Codex's UI renders that as `• Explored └ Read private_network_guard_test.rb,
private_network_guard.rb`, which reads like the client loading the files for
you. It is the opposite: the agent spending a tool call to fetch what it was not
given. If the mention had attached them the `sed` would have been unnecessary.

The full order in the session — prompt at item 4, "I'll inspect the guard and
its focused test" at item 5, `sed` at item 6, patch at item 11, test run at item
14 — is the shape of an agent that has to go and look.

### Codex's `@` is autocomplete, not attachment

The obvious objection to the paste result is that pasting skips the client's own
mention flow. So the run was repeated with the `@` **typed** and each file chosen
from Codex's completion list. What the session stored:

```
Relevant files:
test/lib/restricted_http/private_network_guard_test.rb 
lib/restricted_http/private_network_guard.rb
```

The `@` is **gone**, and what remains is an ordinary path. Codex's `@` is a
filename completer: it is a trigger character the input box consumes while it
helps you type the path, and the message it sends contains no mention at all.

The agent then behaved exactly as in the paste run — item 6 is the same
`sed -n '1,240p' …` over both files, and the contents first appear at record 13.

So the two entry modes differ in what reaches the model, and neither attaches:

| entry | what the model receives | attached |
|---|---|---|
| pasted `@path` | `@path`, literally | no |
| typed `@` + picked | `path`, `@` stripped | no |

This also explains the paste run's oddity, where one of two `@` characters
vanished: the input box treats `@` as a live trigger, so a pasted one can be
consumed as if it had been typed.

**Practical consequence.** In Codex the `@` picker saves you typing a path and
nothing more. If you want Codex to have a file, the only way is to let it read
the file — which it will do, at the cost of a tool call.

### Still open

What a `:line` suffix does in a TUI, and whether Claude's TUI behaves the same
when the mention is typed rather than pasted. Claude attaches pasted mentions,
so the typed path is unlikely to be worse, but it is untested.

## The trials

Five conditions in two families. The `_noline` pair is the one that exercises
the feature; the suffixed pair is kept because it answers a real question about
the form people actually write.

| condition | hint block |
|---|---|
| `none` | one sentence of domain language |
| `bare` | `path:line` |
| `at` | `@path:line` |
| `bare_noline` | `path` |
| `at_noline` | `@path` |

### Claude: `at_noline` vs `bare_noline`, five bugs per cell

The context cost is established. Mann-Whitney U, two-sided, n=5 against n=5:

| app | `bare_noline` median | `at_noline` median | Δ context | U | p |
|---|---|---|---|---|---|
| campfire | 19,209 | 21,544 | **+2,335** | 0.0 | **0.0079** |
| postcraftstudio | 19,205 | 23,288 | **+4,083** | 0.0 | **0.0079** |
| bookmarks | 19,197 | 24,088 | **+4,891** | 0.0 | **0.0079** |

**U = 0.0 in all three.** Every `at_noline` trial used more first-request
context than every `bare_noline` trial — perfect separation, no overlap
anywhere. p = 0.0079 is the smallest value this test can return at n=5 vs n=5,
so this is as strong as the design allows.

The baselines are the tell. Without the mention the first request is almost
exactly the same size every time — campfire's five land between 19,201 and
19,218, a spread of 17 tokens — because it is the fixed system prompt and a
short prompt. With the mention it moves to 20,324–23,771 and varies, because
what varies is the file.

**Nothing else moved.**

| metric | campfire | postcraftstudio | bookmarks |
|---|---|---|---|
| total tool calls | p=0.48 | p=0.58 | p=0.37 |
| output tokens | p=1.00 | p=0.84 | p=0.42 |
| wall seconds | p=0.84 | p=1.00 | p=0.42 |

At one bug per cell the earlier run hinted that `@` bought fewer tool calls and
fewer output tokens. **At five it does not.** Those were noise, and the write-up
said so at the time; this settles it. The mention buys the file's presence and
charges the file's tokens. It does not make the agent do less work.

### The one behavioural difference, and why it is not a cost

`tool_calls_to_first_defect_read` separates too — p=0.0476 in all three apps —
but it moves *up*, and the raw values say why:

| condition | campfire | postcraftstudio | bookmarks |
|---|---|---|---|
| `bare_noline` | 1, 1, 1, 1, 1 | 1, 1, 1, 1, 1 | 1, 1, 1, 1, 1 |
| `at_noline` | 1, 3, 7, 3, 5 | 5, 1, 8, 6, 3 | 6, 3, 1, 3, 7 |

Without the mention the agent's **first tool call is the defect file, in all
fifteen trials**. The prompt names the file, so it opens it. With the mention
that read happens later, or is a re-read before editing, because the file is
already in context and there is nothing to go and fetch.

Read off the metric name this looks like "`@` makes the agent slower to find the
defect", and identical U values in three independent apps should be the clue
that something degenerate is going on rather than a real effect: the
`bare_noline` baseline is the constant 1, every time. It is not a cost. It is a
second, independent confirmation of attachment, arrived at from behaviour rather
than from token counts — and it agrees with `probe_attachment.rb`.

Total tool calls do not change, so the agent is not doing more work. It is doing
it in a different order.

### Claude: `at` vs `bare`, the suffixed pair

| app | `bare` | `at` | Δ |
|---|---|---|---|
| campfire | 19,215 | 19,217 | +2 |
| postcraftstudio | 19,206 | 19,208 | +2 |
| bookmarks | 19,210 | 19,212 | +2 |

Exactly one token per `@` character, three times. Nothing resolves.

### Codex

`context_before_first_tool_call` is null for Codex by design — it meters per
turn, and a turn contains every tool call in it, so there is no first-request
figure.

At five bugs per cell **not one metric separates, in any app**: tool calls,
output tokens, wall seconds and `tool_calls_to_first_defect_read` all come back
p ≥ 0.37, and the last is flat 0 on both sides. Its input totals still swing in
both directions by tens of thousands of tokens, which is tool output volume, not
a mention.

That is the expected shape when the manipulation does nothing, and it is what
the behavioural probe says directly: `@` is not resolved.

Codex ran on `gpt-5.6-sol`, pinned. The earlier 30 trials were unpinned and
their transcripts carry no model field at all, so they are not attributable to a
version and are not pooled with these.

## Every trial fixed its bug

102 of 102, both agents, all five conditions, all fifteen bugs. `fix_verified`
requires a green suite *and* an untouched `test/`. So on tasks this size no hint
style is the difference between solving and not solving; what changes is what it
costs.

That is worth stating plainly because it bounds the whole result. The `@` is not
a correctness aid here. Every condition, including `none` — which withholds the
path entirely — got there.

## The `none` baseline

`none` withholds the defect location and gives one sentence of domain language.
It costs about one extra tool call, which is less than the design assumed, for a
reason worth recording.

**Rails hands the answer over anyway.** The failing test file is named in all
five conditions — it has to be, or the agent must run a whole suite and that
runtime would swamp the effect. But Rails mirrors a test path onto an
implementation path:

```
test/lib/restricted_http/private_network_guard_test.rb   named in every condition
     lib/restricted_http/private_network_guard.rb        one `find` away
```

Observed: in campfire's `none` trial the agent opened with
`find . -name "*private_network*"`, which returned the implementation file before
it had run the suite or read anything.

Only postcraftstudio-01 of the three does not mirror. On that one `none` reached
the defect at tool call 2 against 1 for the others.

`probe_candidates.rb` now flags mirrored candidates; on bookmarks only 3 of 19
plantable commits withhold the defect path.

## What this does not show

- **Five bugs per cell, not fifty.** The context effect separates completely, so
  its p-value is the floor of what this test can report rather than a measure of
  how large the effect is. The null results are the weaker claim: p ≥ 0.37 on
  tool calls, output tokens and wall time means *no effect was detected at this
  size*, not that none exists. A small consistent saving would not show up here.
- **`cond-none` is not uniform across apps.** Seven of the fifteen bugs withhold
  the defect path; eight are mirrors, where dropping `test/` from the named test
  file lands on the implementation file. bookmarks contributes only one of the
  seven, postcraftstudio four. `none` is therefore weakest on bookmarks, and its
  cells should be read per app rather than pooled.
OLD

edits << [<<'OLD', <<'NEW']
- **Wall time is unusable here.** Beyond ordinary noise, the postcraftstudio
  `_noline` trials ran while a probe was using the same machine, so their
  `wall_seconds` are contaminated. Recorded rather than quietly dropped.
OLD
- **Wall time is weak evidence at best.** The grid runs sequentially for this
  reason, but it shares a laptop with whatever else is happening on it. In the
  earlier run the postcraftstudio `_noline` trials overlapped a probe and their
  timings were contaminated outright. Recorded rather than quietly dropped.
- **Wall time is unusable here.** Beyond ordinary noise, the postcraftstudio
  `_noline` trials ran while a probe was using the same machine, so their
  `wall_seconds` are contaminated. Recorded rather than quietly dropped.
- **Only pasted mentions are measured in the TUIs.** Typing `@` and choosing
  from the completion list is a different code path and is untested.
- **One task shape**, a failing Minitest with a named test file.
- **campfire is public** and may be memorised. Its numbers agree with the two
  private apps.

## Where the data is

```
results/                committed
  <bug>/<agent>/<condition>/<timestamp>/
    meta.json           what the trial did, and whether the fix held
    metrics.json        the parsed numbers behind every table above
    prompt.txt          the exact prompt the agent received
    transcript.jsonl    campfire only - raw agent output
    events.jsonl        campfire only - parsed events
    agent.diff          campfire only - what the agent changed
    test_before.txt     campfire only - proof the bug failed first
    test_after.txt      campfire only - proof the fix held

results-raw/            gitignored, everything unfiltered for all three apps
results-manual/         gitignored, TUI sessions from manual_trial.rb
```

The two private apps publish measurements only. `sanitize.rb` refuses to copy
anything at all if a forbidden pattern appears, rather than redacting. It
reported all 30 clean.

```sh
ruby at-file-mentions/scripts/probe_attachment.rb --app campfire --agent claude
ruby at-file-mentions/scripts/probe_mention.rb    --app campfire --agent claude
ruby at-file-mentions/scripts/parse_transcript.rb --all
ruby at-file-mentions/scripts/metrics.rb
```

## The harness was wrong ten times

None were visible until it ran against real data, and the previous session's
notes called it "proven end to end". Details in the commit messages on
`experiment/at-file-mentions`.

1. **Trials could not start** — the only container invocation not going through
   a login shell, so the mise-managed `ruby` was not on `PATH`.
2. **`tool_calls_to_first_defect_read` was uncomputable** — the runner never
   wrote `impl_files` to `meta.json`, so the metric returned nil on every trial,
   indistinguishable from an honest null.
3. **Trials were not hermetic** — `CLAUDE_CONFIG_DIR` pointed at the mounted
   credential store, giving every trial the same writable auto-memory directory.
4. **The hermeticity guard flagged clean runs** — it tested whether a memory path
   exists, which is always true.
5. **`metrics.rb` counted every published trial twice** — the glob `results*`
   matches `results/` and `results-raw/` both.
6. **Postgres could not start** — the agent-owned cluster needed to write its
   socket into a root-owned directory.
7. **`plant_check` started the wrong cluster**, so no Postgres bug could
   reproduce and two good bookmarks candidates were condemned as "NOT A BUG"
   when the suite had never run.
8. **The prompts never exercised the feature under test.** Every hinted path
   carried a `:line` suffix, which stops `@` resolving, so the independent
   variable was inert in both conditions.

9. **`plant_check` could not see bugs that raise.** Its parser matched only
   Minitest's bracketed shape, which Minitest prints for `Failure:` but not for
   `Error:` — an exception carries no location of its own, because it is raised
   wherever it is raised, and the test file appears only in the backtrace. So
   any planted bug that threw scored "NOT A BUG". It rejected `campfire-03`, a
   clean defect: reverting its fix makes the controller call a method the
   account does not have, giving 0 failures and 3 errors, and the regex saw
   neither. `runner.rb` was never affected — it asks whether the suite ran and
   whether the exit was non-zero — so no trial result was wrong, only the
   pre-flight gate that decides which bugs exist.
10. **The postcraftstudio needle was the filename.** `probe_attachment.rb`
    proves attachment by asking for a method name the agent could not produce
    without reading the file. Its needle was `api_auth` — which is the module
    name *and* the basename of `api_auth.rb`, so an agent that could not see the
    file at all could answer it straight off the path. The one check the whole
    result leans on could have reported ATTACHED for a file that was never
    attached. Now `verified_token`, a private method in that file.

Number 8 is the one that mattered most. The first seven were caught by the
harness's own assertions. That one was not caught by anything: the trials ran
green, the measurements were internally consistent, and the write-up confidently
concluded that `@` does nothing — until someone asked whether that could
possibly be true.

Every check in this harness verified that a trial ran correctly. None verified
that the manipulation had any effect. `probe_attachment.rb` is that check now,
and it should be run before any comparison between conditions is believed.

### The pattern in all ten

The defects that survived longest are the ones that made the experiment quietly
**smaller** rather than visibly broken. A trial that fails loudly gets fixed the
same day. A good bug silently rejected just looks like a bug that did not pan
out, and the grid shrinks by one with nobody the wiser — which is how
`bookmarks-01` was condemned by a Postgres cluster that never started, and how
`campfire-03` was condemned by a regex.

Two of the ten (9 and 10) were false *rejections* and one near-miss was a false
*acceptance*. Both directions are worth guarding, but they fail differently: a
false rejection costs data and looks like nothing, while a false acceptance
would have put a wrong headline in this file. The only reason number 9 surfaced
is that its verdict carried an incongruous "3 errors" — the number that did not
fit the story it was telling.

## Next

All three of the previous list are done: the grid is at five bugs per app, the
TUIs were driven by hand for both agents, and the suffixed `bare`/`at` pair was
dropped from the run — rendered still, for the identity checks, but not spent
container time on.

What is left is narrower:

- **Close the two TUI gaps.** What a `:line` suffix does in a TUI, and whether
  Claude's TUI behaves the same typed as pasted. Claude attaches pasted
  mentions, so typed is unlikely to be worse, but it is untested.
- **The null results deserve a bigger n if anyone cares about them.** p ≥ 0.37
  on tool calls and output tokens rules out a large effect, not a small one. The
  grid is resumable and blocked by bug, so more bugs slot in without re-running
  anything.
- **`cond-none` is worth re-examining per app.** It is measuring something
  different on bookmarks, where four of five bugs hand over the defect path
  through the test file's name, than on postcraftstudio, where four of five do
  not.
- **One task shape is still the biggest limitation.** Everything here is a
  failing Minitest with the test file named. Whether `@` pays off differently
  when the agent has to find the failure itself is untouched.
