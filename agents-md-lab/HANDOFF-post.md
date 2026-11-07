# Handoff: write a post about AGENTS.md in Claude Code

You are helping Lucian write a blog post from an experiment in this folder (`agents-md-lab/`).
Read these first, in this order:

1. `README.md`, sections "Findings" and "AGENTS.md is not a CLAUDE.md with another name".
2. `MANUAL-CHECK.md`, the import-order check with the raw capture output and controls.
3. `results/2026-11-07-first-run-claude.md`, the full run table and the "What the docs say" list.
4. `lib/scenarios.rb`, if you need the exact files each scenario built.

Do not re-run the lab or change code. Your job is the writing.

## The claim

AGENTS.md in Claude Code is a second-class instruction file, by design and as documented.
The experiment checked every rule in the docs instead of trusting them, and they held. One
sentence in the docs is wrong, and it is about `@imports`, not about AGENTS.md.

## The three things to say, in strength order

1. **Docs error, request-level evidence.** The docs say that with `@AGENTS.md` at the top of
   CLAUDE.md "Claude reads the imported file first, then the rest". The captured request shows
   the CLAUDE.md block, with the literal `@AGENTS.md` line still in it, and AGENTS.md appended
   as its own block after it. `/context all` lists the files in the same order. Controls show
   this is how every `@import` works. Quote the docs sentence verbatim, it is in MANUAL-CHECK.md.
2. **The private file trap.** A `CLAUDE.local.md` with personal notes silently turns AGENTS.md
   off. Fix: Project instructions = `claude-md-and-agents-md`, or `@AGENTS.md` in a CLAUDE.md.
3. **The shell trap.** A subfolder CLAUDE.md loads after a single-file `cat`. A subfolder
   AGENTS.md loads only after the Read tool. Claude exploring with shell commands never sees it.

Then the comparison table from the README, as is.

## Method, in one paragraph

Each scenario builds a tiny git repo in a temp folder with one random marker per instruction
file. For Codex, `codex debug prompt-input` prints the exact prompt, so the check is free and
exact. For Claude there was no equivalent, so Day 1 asked `claude -p` to list the markers it
had in context and marked a run SUSPECT if Claude opened an instruction file itself. Day 1
follow-up added `bin/capture-prompt`, a local HTTP server that `ANTHROPIC_BASE_URL` points at,
which records the real request and answers 400 so no model is called. That is the Claude side
of `codex debug prompt-input`.

## Evidence standard, state it plainly

- Import order: request capture plus `/context all`. No model in the loop. Strongest.
- Every other row: the model's own report, consistent across runs on haiku and sonnet, no
  instruction file opened by Claude. Good, but a self-report.
- Not verified: Write or Edit as a subfolder AGENTS.md trigger; reload after `/compact`.

## Facts to get right

- Claude Code version 2.1.318, run on 2026-11-07. Docs page: https://code.claude.com/docs/en/memory#agents-md
- Memory files are not in the API `system` field. They travel inside a `<system-reminder>` in
  the first user message, as separate `Contents of <path> (...)` blocks.
- Default Project instructions value is `claude-md-or-agents-md`. The lab forced it on every run
  so the user's own `/config` choice could not change results.
- Not read by Claude anywhere: `AGENTS.local.md`, `AGENTS.override.md`, anything under
  `.agents/`. `.claude/AGENTS.md` is read.
- Codex reads `AGENTS.override.md` instead of `AGENTS.md` and has no import syntax. Codex
  results are exact (debug output, no model).

## Tone and framing

- This is not a "gotcha" post. Most differences are documented. The value is that they were
  checked, and one docs sentence did not survive the check.
- Keep the docs error separate from the AGENTS.md differences. It applies to CLAUDE.md too.
- Write for developers who share one AGENTS.md between Codex and Claude Code. Lead with what
  breaks for them, then show how it was checked.
- Lucian's writing skill is `writing-in-my-style`. Use it for the draft.
- Simple technical English, short sentences, no hedging where the evidence is clear.

## Open questions you may raise but must not answer as fact

- Whether the docs sentence describes an older Claude Code version.
- Whether Anthropic intends imports to be appended rather than spliced. The behaviour is
  consistent, the intent is unknown.
