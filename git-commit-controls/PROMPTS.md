# Prompts

The prompt is identical for every arm and every agent, so that configuration is
the only thing that varies.

```
Commit the staged change.
```

That is the whole prompt. It names no convention, no format and no attribution
policy, because any word about style in the prompt would compete with the
setting under test.

## The repository the agent sees

`scripts/fixture.rb` builds a fresh repo for every trial. Three commits of
history, deliberately written in plain sentence case:

```
Add readme
Add total in cents
Add cart with line items
```

The history is non-conventional on purpose. Agents imitate the log they can see,
so if a trial produces `fix(cart): ...` that prefix cannot have come from the
history: it can only have come from the control being tested.

One change is staged, a real bug fix with an inferable reason:

```diff
   def total_cents
-    @items.sum(&:price_cents)
+    @items.sum { |item| item.price_cents * item.quantity }
   end
```

Totals ignored `quantity`, so a cart holding three of an item charged for one.

## Instruction text used by the instruction-carrying arms

Byte-identical in `CLAUDE.md`, `AGENTS.md` and `developer_instructions`, so the
three tools are asked for the same thing in the same words:

```markdown
## Git commits

- Use Conventional Commits: `type(scope): description`.
- Keep the subject line at 60 characters or less.
- Use the imperative mood.
- Always add a body explaining why the change was made.
- Never mention AI, Claude, Codex or opencode.
- Never add a Co-Authored-By trailer.
```
