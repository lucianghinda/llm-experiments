# Results

100 trials. The pilot is 4 tasks × 2 layouts × 2 agents × 5 repeats = 80. Two
follow-up arms add 10 each, on the cross-layer task only: each layout plus a
document saying where things live. Every cell full, every trial passed, none
aborted.

Every number here comes from `scripts/report.rb`, which writes
[`results/tables.md`](results/tables.md) from the trials themselves. Nothing was
typed by hand.

## The short version

**The assumption, as stated, is wrong. The cost it predicts is real anyway.**

The assumption was that an agent on a conventional Rails app *already knows
where to look*, so it searches less. The first half of that never happened:

> **Zero-search navigation: 1 out of 100.**
>
> One trial — a Codex run on the conventional layout, carrying a map — opened
> its first command with `rg … app/models/room.rb`, supplying the path from
> knowledge instead of looking for it. Every other trial in every condition
> searched first. Not once in the bare conventional layout, where
> `app/models/room.rb` sits exactly where the convention says it should.

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

The sharpest result in the pilot is a mechanism metric, not a token count.
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

And a document refunds it. A 2.5 KB file listing which directory holds models,
controllers and migrations took **−32% off the scrambled layout for Claude
(p=0.008) and −31% for Codex**.

But the control arm says that is not mainly the map's doing. The same kind of
document on the *conventional* layout — one that mostly restates Rails defaults
and tells the agent almost nothing it could not have guessed — saved **−40%
(p=0.008), with the five trials separating completely from the five without it.**

> **The biggest effect in this experiment is not the layout. It is whether the
> repository has a `CLAUDE.md` at all.**

The layout still costs something on top: with a document on both sides, Claude
pays +42% for the scrambled tree (p=0.095). Convention and documentation are not
alternatives. They add.

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

20 trials, `feature-room-topic` only — the cross-layer task, where the penalty
was. Each layout gets a map of itself, written in as the file the agent reads
without being told to: `CLAUDE.md` for Claude, `AGENTS.md` for Codex. Both name
directories and no file paths, so they hand over the layout and not the answer,
and both name the same three `.rb` files, none of which is a target.

The second arm is the control, and it is the reason the first arm's reading
changed. It holds *having a document* constant and removes the only thing the
scrambled map had to tell you: a conventional layout's map mostly restates Rails
defaults — models in `app/models/`, one route file, tests mirroring the source
tree — so it is a document that says almost nothing an agent could not guess.
1,923 bytes against the scrambled map's 2,487.

| agent | metric | conv | conv+map | scr | scr+map | conv → conv+map | scr → scr+map | conv+map → scr+map |
|---|---|---|---|---|---|---|---|---|
| claude | input tokens | 3,119,564 | 1,868,371 | 3,899,138 | 2,657,817 | **−40%** (0.008) | **−32%** (0.008) | +42% (0.095) |
| claude | search calls | 20 | 15 | 25 | 20 | −25% (0.024) | −20% (0.008) | +33% (0.056) |
| claude | searches before first target | 2 | 2 | 5 | 2 | +0% (0.278) | **−60%** (0.008) | +0% (0.444) |
| codex | input tokens | 570,090 | 613,826 | 733,778 | 506,662 | +8% (0.690) | −31% (0.095) | −17% (0.421) |
| codex | tool calls | 11 | 8 | 11 | 8 | −27% (0.016) | −27% (0.056) | +0% (0.325) |

### The document is worth more than the layout

Claude's conventional trials cost 40% less with a map than without, and the two
sets do not overlap at all: `1.71, 1.74, 1.87, 1.91, 2.37` million against
`2.68, 2.86, 3.12, 3.41, 5.80`. Every documented trial beat every undocumented
one. That is a larger effect than the scramble ever produced, from a file whose
entire content is "Rails is where Rails puts things".

So the previous arm's most eye-catching number was the confound, exactly as
flagged. `scrambled-mapped` beating `conventional` was never evidence that a
documented nonstandard layout beats convention. It was evidence that a
documented repository beats an undocumented one, which is true of both layouts
and has nothing to do with the scramble.

### What the layout information specifically buys

One metric separates the two effects cleanly. `searches_before_first_target` —
how much hunting happens before the agent opens the first file it actually
needs — moves like this for Claude:

```
conventional      2  ->  with map  2      (+0%, p=0.278)
scrambled         5  ->  with map  2      (-60%, p=0.008)
```

The layout information does exactly one job, and only where the layout is
unguessable. On a conventional tree the agent was already finding the first
target in two searches, and telling it `app/models/` changed nothing. On a
scrambled tree it took five, and telling it `platform/core/entities/` took it
straight back to two — `2, 2, 2, 2, 2`, five trials, no spread.

Everything else the document buys is layout-independent. Whatever a `CLAUDE.md`
does to make an agent cheaper — orienting it, stopping it exploring for
context it can be handed — it does on either tree, and it is the larger half.

### The layout penalty survives being documented

With a document on both sides, Claude still pays **+42%** for the scrambled tree
(p=0.095) — wider than the +25% it paid undocumented, because the document helps
the conventional layout more (−40%) than the scrambled one (−32%). Codex points
the other way at −17% (p=0.421) and settles nothing. Neither reaches
significance, and the two agents disagree on sign, so this is the weakest claim
here and the one most in need of more repeats.

What it does rule out is the tidy version of the earlier conclusion. Writing the
layout down is not a substitute for having a guessable one; on Claude's numbers
the best cell in the whole experiment is conventional *and* documented
(1,868,371) and the worst is scrambled and not (3,899,138), a factor of 2.1.

### The document shrank the diff. The layout did not

Tokens are one currency; the code a trial leaves behind is the other, and it is
measured independently, from `agent.diff` rather than from the transcript.
Median lines added to tracked files on the cross-layer task, for Claude:

```
conventional            220        scrambled            214     (-3%, p = 0.841)
conventional + map      126        scrambled + map      150     (-43% and -30%)
```

The layout never moved this number: 220 against 214 is flat. The document cut it
43% on the conventional tree (p=0.008) and 30% on the scrambled one (p=0.056),
and files touched went 14 to 10 and 14 to 11 (both p=0.024). Codex shows the
same direction at smaller scale: 31 to 24 and 34 to 23.

So the intervention that cut input tokens 40% also cut the code written 43%,
measured a different way, which makes the token result hard to dismiss as an
accounting artifact. What the extra code was: without a document, every
conventional Claude trial also edited the room nav partial and the two
controller subclasses, four of five edited the translations helper, and two
touched a stylesheet — none of which the prompt asked for and none of which the
acceptance test checks. With the map, on the conventional tree, the stylesheet
edits stopped and the helper edits dropped to one in five. Why orientation
narrows scope is a question this data can only point at: an agent that explores
less encounters fewer files, and files it never reads are files it never edits.

### One observation across agents, recorded with its caveat

Claude's median passing change on the conventional layout is 220 added lines
across 14 files. Codex's is 31 lines across 8. The ranges do not overlap
(186–235 against 22–39, p=0.008), both pass the same acceptance test, and both
leave the same 348-test suite green. On the test-writing task the same split is
20 lines against 7.

This is the one cross-agent comparison in these results, and it is a comparison
of models, not layouts: diff lines mean the same thing for both agents, unlike
tokens, but nothing here says which change is better. No trial's diff was ever
scored for quality — passing is the only bar — and "minimal" and "incomplete"
can look identical from a line count, as can "thorough" and "padded".

### Codex spent fewer calls and not fewer tokens

On the conventional layout the map cut Codex's tool calls 27% (p=0.016) and its
search calls 40% (p=0.048) while input tokens went the wrong way by 8%
(p=0.690). Fewer, larger calls is a plausible reading of that and this
experiment cannot confirm it. It is a reminder that a token total and a call
count are different measurements and only one of them is what a bill is made of.

### What the maps cost

Nothing had to be subtracted: a map sits in the file the agent loads, is re-sent
with the context every turn, and lands in `input_tokens` through the same door it
would in a real repository. At about 2 KB over the tool calls a trial takes, that
is on the order of 1% of the trial against savings of 30–40%.

Worth stating plainly rather than hiding in the win: this tests whether
documentation *works*, not whether it pays for itself. At 1% against 40% the
second question does not become interesting. It would if the document were fifty
times longer.

### What to hold against it

**The scrambled arms and their baselines were run a day apart.** The bare
`conventional` and `scrambled` cells ran 2026-08-22; both mapped arms ran
2026-08-23. So `conv → conv+map` and `scr → scr+map` each compare across days,
and the grid's usual protection — blocking conditions together, rotating order
within the block — does not apply to a reused baseline. Machine or model drift
between those days would land on the map in both cases.

Two things argue against drift explaining the result. The `2 → 5 → 2` shape on
searches-before-first-target is too specific for a general slowdown. And the one
comparison with no reuse in it at all — `conv+map → scr+map`, both arms run on
the same day, an hour apart — is the one that still shows a layout penalty. But
re-running the two bare arms today would settle it, and that has not been done.

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

**Nothing failed.** 100 of 100 trials passed their scripted acceptance check —
40 conventional, 40 scrambled, 10 mapped on each layout. The scramble made no
task impossible, and it did not push either agent into producing worse work —
which rules out the cheapest way a condition can look cheap, by giving up
sooner. The maps' savings are subject to the same check and pass it: 5 of 5 in
both mapped arms, so a documented trial did not buy its 40% by doing less.

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
- **Only successful trials count toward cost.** Since all 100 passed, this
  changed nothing, but it was the rule going in.
- **Roughly 80 comparisons appear in the tables**, once the maps' three pairings
  are counted. A single p=0.032 among that many looks is about what chance
  produces. The p=0.008 results survive that scrutiny more comfortably — two of
  them are complete separations of five against five — but the maps' evidence
  rests on one task, and the strongest numbers are all Claude's.
- **The maps were tested on one task only.** `feature-room-topic` is where the
  penalty was, which is why it was chosen, but it means each document's effect
  is a single cell per agent rather than a direction across tasks. The
  pre-registered standard — same direction across tasks — cannot be applied to
  them, because there is only one.
- **The two agents disagree about `conv+map → scr+map`**, +42% against −17%,
  neither significant. That comparison is the cleanest in the experiment by
  design and the least conclusive in fact.
- **One map is 23% shorter than the other**, because a conventional layout
  honestly needs less description. Padding it to match would have added content
  that is not a layout map. So a small part of the `conv+map` versus `scr+map`
  gap is a difference in document length, not in layout.
- **The bare arms ran a day before the mapped ones.** See the note in the
  follow-up section; a reused baseline gives up the grid's usual protection
  against drift.

## What this means in practice

If you are choosing an architecture, the finding is narrower than the assumption
and more useful than it looks.

A nonstandard layout does not stop an agent working, does not make it fail more,
and costs nothing when it is answering a question about your code. It starts
costing 25–44% when the agent has to *change* code in several places at once —
because it has to relocate each of those places by searching, and searching is
the only navigation an agent does.

**But the layout is the smaller of the two things measured here.** A page of
prose in `CLAUDE.md` took 40% off Claude's conventional trials — every documented
run cheaper than every undocumented one — and it did that on a tree where the
document mostly restates Rails defaults. The scramble, at its worst, cost 25–44%.
The cheapest change available to most repositories is not rearranging anything.
It is writing the file.

Which is a boring recommendation, and it is the one the numbers support most
strongly. If you have one thing to do: add a `CLAUDE.md` or `AGENTS.md` that says
where things are and how to run the tests. It is a page. It costs about 1% of a
request and it is the largest effect in a hundred trials.

**Convention still earns its keep on top of that.** With documents on both sides
Claude paid 42% more for the scrambled tree, and the best cell in the experiment
is conventional *and* documented — 1.87M against 3.90M for scrambled and bare, a
factor of 2.1 between the two ends. Convention and documentation are not
substitutes doing the same job; they stack. Codex disagrees on that comparison,
neither agent's number is significant, and it is the claim here most in need of
more repeats.

**What none of it changed: agents do not predict paths.** 99 trials out of 100
searched before reaching a file they needed, including on a conventional layout
handed a document naming the directory. Searching is the only navigation an agent
does. Convention and a map both work by making that search land sooner — one by
being guessable, the other by being read — and only one of them is available to a
codebase that already exists.
