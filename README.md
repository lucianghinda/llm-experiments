# llm-experiments

Small, self-contained experiments about Ruby code and LLM behaviour. Each one
keeps its raw outputs, the exact prompts, and the scripts that measure the
results, so anyone can check the numbers instead of trusting the summary.

## Experiments

| Folder | Question | Runs |
|---|---|---|
| [`simplified-technical-english/`](simplified-technical-english/) | Does asking an agent for "Simple Technical English" change how it explains code, and what does that cost in content? | 60 |

## Conventions

- One folder per experiment, named after the question it asks.
- `README.md` in that folder holds the design, the results and the caveats.
- `PROMPTS.md` holds the exact prompts, unedited.
- Raw model output is committed as produced. Nothing is reworded or trimmed.
- Measurement is done by script, never by eye, so a claim can be re-run.
- No absolute paths and no private source code. Where a private checkout was
  used, `<app-root>` marks it and the code under test is copied in as
  `00-source-*.rb`.
