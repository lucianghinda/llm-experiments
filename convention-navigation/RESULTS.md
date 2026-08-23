# Results

90 trials. The pilot is 4 tasks × 2 layouts × 2 agents × 5 repeats = 80. A
follow-up adds a third layout — the scrambled one plus a document saying where
things live — on the cross-layer task only, for 10 more. Every cell full, every
trial passed, none aborted.

Every number here comes from `scripts/report.rb`, which writes
[`results/tables.md`](results/tables.md) from the trials themselves. Nothing was
typed by hand.

## The short version

**The assumption, as stated, is wrong. The cost it predicts is real anyway.**

The assumption was that an agent on a conventional Rails app *already knows
where to look*, so it searches less. The first half of that never happened:

> **Zero-search navigation: 0 out of 90.**
>
> Not one trial, in any of the three layouts, reached a file it needed without
> grepping for it first. Not once in the conventional layout, where
> `app/models/room.rb` sits exactly where the convention says it should — and
> not once in the mapped layout either, where the agent was handed a document
> naming the directory before it started.

Agents do not predict paths. They grep for identifiers and open what comes back.
And because the scramble renames nothing — 708 identifiers, identical counts on
both sides — grep costs the same either way. That is why **finding things is
free**: across both locate tasks and both agents, the scrambled layout cost
+4%, +1%, −10% and +0% in input tokens, none of it significant.

But **changing things is not free.** On the two tasks that write code, the
scrambled layout cost more in three of four cells:

| agent | task | conventional | scrambled | change | exact p |
|---|---|---|---|---|---|
| codex | test-direct-type | 110,725 | 159,613 | **+44%** | 0.032 |
| codex | feature-room-topic | 570,090 | 733,778 | **+29%** | 0.056 |
| claude | feature-room-topic | 3,119,564 | 3,899,138 | **+25%** | 0.151 |
| claude | test-direct-type | 568,377 | 531,639 | −6% | 0.548 |

The sharpest result in the experiment is a mechanism metric, not a token count.
Claude's search calls on the cross-layer task separate completely:

```
conventional:  18, 18, 20, 20, 21
scrambled:     24, 25, 25, 26, 26        +25%, exact p = 0.008
```

Every scrambled trial searched more than every conventional trial. There is no
overlap.

**So the mechanism is not the one in the assumption.** Convention does not save
an agent from searching — it never searched less. Convention saves it from
searching *repeatedly*, when a single change has to land in five places at once
and the agent has to locate each of them.

And that is exactly the cost a document can refund. A 2.5 KB file listing which
directory holds models, controllers and migrations gave back the whole penalty:
**−32% input tokens against the scrambled layout for Claude (p=0.008), −31% for
Codex.** The layout was never the thing that cost money. Not knowing it was.

## What each task cost

Medians over five trials that passed. Full per-trial values in
[`results/tables.md`](results/tables.md).

### Finding things: no effect

| agent | task | conventional | scrambled | change | exact p |
|---|---|---|---|---|---|
| claude | locate-direct-type | 209,035 | 218,157 | +4% | 0.690 |
| claude | locate-generated-secret | 62,866 | 63,745 | +1% | 0.841 |
| codex | locate-direct-type | 54,109 | 48,776 | −10% | 0.310 |
| codex | locate-generated-secret | 47,227 | 47,402 | +0% | 0.421 |

Codex's tool calls and search calls were *identical* on both layouts, on both
tasks: 2 calls, 1 search, every time. The layout made no difference whatsoever
to a lookup.

### Changing things: 25% to 44%, on three cells of four

`feature-room-topic` adds a field that has to reach a migration, a model
validation, a controller's strong params and a view. `test-direct-type` writes a
test that has to go where tests belong and has to fail when the rule is removed.

Claude's exception is real and unexplained: on `test-direct-type` it cost 6%
*less* on the scrambled layout, with the ranges overlapping almost entirely
(323k–615k against 394k–671k). One cell out of four going the other way is what
n=5 cannot resolve.

## The follow-up: writing the layout down

10 trials, `feature-room-topic` only — the cross-layer task, where the penalty
was. Same scrambled tree, plus `map.md` written in as the file each agent reads
without being told to: `CLAUDE.md` for Claude, `AGENTS.md` for Codex. 2,487
bytes. It names directories — models are in `platform/core/entities/`, migrations
in `db/changes/` — and no file paths, so it hands over the layout and not the
answer.

**The map gives the whole penalty back.**

| agent | metric | conventional | scrambled | mapped | scrambled → mapped | exact p |
|---|---|---|---|---|---|---|
| claude | input tokens | 3,119,564 | 3,899,138 | 2,657,817 | **−32%** | 0.008 |
| codex | input tokens | 570,090 | 733,778 | 506,662 | **−31%** | 0.095 |
| claude | search calls | 20 | 25 | 20 | −20% | 0.008 |
| claude | searches before first target | 2 | 5 | 2 | −60% | 0.008 |
| claude | files read | 36 | 38 | 30 | −21% | 0.032 |
| codex | tool calls | 11 | 11 | 8 | −27% | 0.056 |

The mechanism metrics are the convincing part, because they say the map worked
*the way a map should*. Claude's searching before it opens the first file it
needs runs `2 → 5 → 2`: the scramble tripled it, the map put it back exactly.
Per-trial, the mapped arm is `2, 2, 2, 2, 2` — five trials, no spread at all.
Search calls do the same thing, `20 → 25 → 20`, and the difference from
conventional is p=0.714, which is as close to "no difference" as five trials can
report.

**But it still never navigated without searching. 0 out of 10.** The agent is
handed a document that says models live in `platform/core/entities/`, and it
greps anyway. Both agents, every trial. So the map does not teach an agent to
predict paths — nothing in this experiment ever did. It makes the searches it
was always going to run land on the first try instead of the third.

### Mapped came in under conventional too, and that comparison is not clean

Claude's mapped arm cost 15% less than the conventional layout (p=0.056), Codex's
11% less (p=0.421). It is tempting to read that as "a documented nonstandard
layout beats Rails convention", and it does not support that.

**Only the mapped arm carries an agent-instruction file at all.** campfire ships
no `CLAUDE.md` or `AGENTS.md`, so conventional and scrambled both ran without
one. A mapped trial beating conventional could be the map, or it could be the
mere presence of *any* orienting document. This experiment cannot separate them.
The arm that would — conventional plus the same kind of document — has not been
run, and until it is, the honest claim stops at "the map recovers what the
scramble cost".

### What the map cost

Nothing had to be subtracted, because the map's tokens are already inside the
numbers above: it sits in the file the agent loads, so it is re-sent with the
context on every turn and lands in `input_tokens` through the same door it would
in a real repository. At 2,487 bytes over the 61 tool calls a mapped Claude
trial takes and the 8 Codex takes, that is on the order of 1% of the trial —
against a 30% saving.

That ratio is worth stating plainly rather than hiding in the win: this is a
test of whether documentation *works*, not of whether it pays for itself. At 1%
against 30% the second question does not become interesting. It would if the
document were fifty times longer.

### One thing to hold against all of it

The scrambled baseline was run on 2026-08-22 and the mapped arm on 2026-08-23.
The grid normally defends against machine and model drift by blocking conditions
together and rotating their order within a block — that protection does not
exist here, because the baseline was reused from the earlier session rather than
re-run alongside. Any drift between those two days lands entirely on the map.
The mechanism metrics argue against drift being the explanation, since `2 → 5 →
2` is too specific a shape for a general slowdown, but re-running the scrambled
arm today would settle it and has not been done.

## The pre-registered rule, and why it does not settle this

The rule fixed before any trial ran: the assumption is supported if scrambled
costs more **in the same direction across tasks**, by a sign test, and if the
search counts move the same way.

| agent | metric | scrambled higher on | sign test p |
|---|---|---|---|
| claude | input tokens | 3/4 tasks | 0.625 |
| claude | tool calls | 3/3 non-tied tasks | 0.250 |
| claude | search calls | 3/3 non-tied tasks | 0.250 |
| codex | input tokens | 3/4 tasks | 0.625 |

**It does not reach significance, and it could not have.** With four tasks, a
perfect 4-for-4 sweep gives an exact two-sided p of 0.125. The primary analysis
was arithmetically incapable of producing a p below 0.05 no matter what the
trials showed. That is a design error, and it is mine: the decision rule was
written to resist cherry-picking a single lucky p-value, which it does, but
nobody checked that its own floor sat below the threshold it was being asked to
clear.

So the honest position is that the pre-registered test is uninformative here,
and what remains is the per-task evidence: three of four write cells up 25–44%,
one mechanism metric separating completely at p=0.008, and four locate cells
flat. That is a pattern, not a proof.

## What did not move

**Nothing failed.** 90 of 90 trials passed their scripted acceptance check —
40 conventional, 40 scrambled, 10 mapped. The scramble made no task impossible,
and it did not push either agent into producing worse work — which rules out the
cheapest way a condition can look cheap, by giving up sooner. The map's saving is
subject to the same check and passes it: 5 of 5, so it did not buy its 30% by
doing less.

**Migrations landed in the right place.** The scrambled variant reads migrations
from `db/changes`, and a migration written into `db/migrate` would never be
applied, so the column would never appear and the trial would fail. It never
happened. Both agents found the configured path every time.

## Caveats

- **Four tasks is too few for the primary analysis**, as above. Six to eight
  would put the sign test's floor under 0.05.
- **One app, one week, one machine.** campfire is public and probably memorised,
  so this cannot separate "the model knows Rails" from "the model knows
  campfire". Repeating the write-heavy tasks on a private app is the next thing
  worth doing, and the harness already supports it.
- **The scramble is conservative, so these are lower bounds.** File basenames
  are unchanged, `lib/` does not move, and system tests stay put. Only
  directory-level prediction was removed.
- **Agents are never pooled.** Claude and Codex report tool use differently and
  their token accounting differs; every comparison here is within one agent.
- **Only successful trials count toward cost.** Since all 90 passed, this
  changed nothing, but it was the rule going in.
- **Roughly 50 comparisons appear in the tables**, once the map's two pairings
  are counted. A single p=0.032 among that many looks is about what chance
  produces. The p=0.008 results are more than that, but the map's evidence rests
  on one task, and its strongest numbers are all Claude's.
- **The map was tested on one task only.** `feature-room-topic` is where the
  penalty was, which is why it was chosen, but it means the map's recovery is a
  single cell per agent rather than a direction across tasks. The pre-registered
  standard for the pilot — same direction across tasks — was never applied to
  the map, because there is only one.
- **The map arm ran a day after its baseline.** See the note in the follow-up
  section; the reused baseline gives up the grid's usual protection against
  drift.

## What this means in practice

If you are choosing an architecture, the finding is narrower than the assumption
and more useful than it looks.

A nonstandard layout does not stop an agent working, does not make it fail more,
and costs nothing when it is answering a question about your code. It starts
costing 25–44% when the agent has to *change* code in several places at once —
because it has to relocate each of those places by searching, and searching is
the only navigation an agent does.

**And the remedy is cheap.** 2.5 KB of prose naming which directory holds what
took the cross-layer penalty back to zero, on both agents, on the task where the
penalty existed. If your architecture is nonstandard, the finding does not say
rearrange it. It says describe it, in the file the agent already reads, and the
description does not have to be long — this one is a page.

The reason that works follows from the first finding rather than sitting beside
it. An agent never predicts a path; it always searches. A layout convention and
a `CLAUDE.md` are therefore not alternatives — they are two ways of doing the
same job, which is making the *next* search land. Convention does it by being
guessable. A map does it by being read. Only one of those is available to a
codebase that already exists.

What is not established: that a documented nonstandard layout beats a
conventional one. The mapped arm did come in under conventional, but no
conventional trial carried a document of any kind, so that comparison is
measuring two things at once. The arm that separates them — conventional plus
the same document — is the next thing to run, and it is 10 trials.
