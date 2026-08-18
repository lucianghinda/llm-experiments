# llm-experiments

Small, self-contained experiments about Ruby code and LLM behaviour. Each one
keeps its raw outputs, the exact prompts, and the scripts that measure the
results, so anyone can check the numbers instead of trusting the summary.

## Experiments

| Folder | Question | Runs |
|---|---|---|
| [`simplified-technical-english/`](simplified-technical-english/) | Does asking an agent for "Simple Technical English" change how it explains code, and what does that cost in content? | 60 |
| [`statusline-per-project/`](statusline-per-project/) | Can a Claude Code status line be set per project, so two folders show different bars? | 2 sessions |
| [`at-file-mentions/`](at-file-mentions/) | Does writing a file path as `@path/to/file.rb` instead of `path/to/file.rb` change what an agent does and what it costs? | harness built, not yet run |
| [`startup-context/`](startup-context/) | What does an agent load before it starts work, where does it come from, and which parts can be turned off? | 70 |

## Shared tooling

[`containers/`](containers/) is a reusable clean room: each trial runs in a fresh
Apple container with freshly installed agent CLIs and no host state. It exists
because a plain `claude -p "reply OK"` on my Mac arrives carrying 8 MCP servers,
32 tools and about 59,000 tokens of context before the task starts, which is
larger than most effects worth measuring. `startup-context/` is the experiment
that measured that number, took it apart, and did the same for Codex and
opencode.

## Conventions

- One folder per experiment, named after the question it asks.
- `README.md` in that folder holds the design, the results and the caveats.
- `PROMPTS.md` holds the exact prompts, unedited.
- Raw model output is committed as produced. Nothing is reworded or trimmed.
- Measurement is done by script, never by eye, so a claim can be re-run.
- No absolute paths and no private source code. Where a private checkout was
  used, `<app-root>` marks it and the code under test is copied in as
  `00-source-*.rb`.
