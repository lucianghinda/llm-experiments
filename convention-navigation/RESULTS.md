# Results

80 trials. 4 tasks, 2 layouts, 2 agents, 5 repeats each. Every cell full, every
trial passed, none aborted.

Every number here comes from `scripts/report.rb`, which writes
[`results/tables.md`](results/tables.md) from the trials themselves. Nothing was
typed by hand.

## The short version

**The assumption, as stated, is wrong. The cost it predicts is real anyway.**

The assumption was that an agent on a conventional Rails app *already knows
where to look*, so it searches less. The first half of that never happened:

> **Zero-search navigation: 0 out of 80.**
>
> Not one trial, in either layout, reached a file it needed without grepping
> for it first. Not once in the conventional layout, where `app/models/room.rb`
> sits exactly where the convention says it should.

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

**Nothing failed.** 80 of 80 trials passed their scripted acceptance check,
40 in each layout. The scramble made no task impossible, and it did not push
either agent into producing worse work — which rules out the cheapest way a
condition can look cheap, by giving up sooner.

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
- **Only successful trials count toward cost.** Since all 80 passed, this
  changed nothing, but it was the rule going in.
- **Roughly 32 comparisons appear in the tables.** A single p=0.032 among them
  is about what chance produces at that many looks. The p=0.008 separation is
  more than that, but it is one metric on one task for one agent.

## What this means in practice

If you are choosing an architecture, the finding is narrower than the assumption
and more useful than it looks.

A nonstandard layout does not stop an agent working, does not make it fail more,
and costs nothing when it is answering a question about your code. It starts
costing 25–44% when the agent has to *change* code in several places at once —
because it has to relocate each of those places by searching, and searching is
the only navigation an agent does.

Which also suggests where the remedy is. The `scrambled-mapped` condition — the
same scrambled layout plus a file documenting where everything lives — is
implemented and was never run, because phase 1 only needed two layouts. If a map
recovers the write-task cost, then the answer for a nonstandard codebase is not
to rearrange it but to describe it. That is the obvious next experiment.
