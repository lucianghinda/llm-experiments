# Prompts

One prompt, used unchanged for every agent, every condition and every repeat.

## `prompts/probe.txt`

```
Reply with exactly: OK
```

## Why this prompt

The experiment measures what an agent carries before it does anything, so the
task has to be one no configuration can help with and no tool call can serve.
"Reply with exactly: OK" is answerable from the prompt alone: a run that reads a
file, greps, or calls an MCP server has failed the check, not passed it.

Everything measured therefore arrives before the first token of work: the system
prompt, the tool schemas, the skill and command catalogues, the memory files,
and whatever the hooks injected. The number is the floor of every later request
in that session, not a one-off.
