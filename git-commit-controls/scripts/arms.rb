# frozen_string_literal: true

# Declarative arm table. An arm is a named configuration applied to a throwaway
# repo before the agent is asked to commit. Everything an arm writes is recorded
# here verbatim, so a reader can reproduce the cell without reading the runner.

COMMIT_RULES = <<~MD
  ## Git commits

  - Use Conventional Commits: `type(scope): description`.
  - Keep the subject line at 60 characters or less.
  - Use the imperative mood.
  - Always add a body explaining why the change was made.
  - Never mention AI, Claude, Codex or opencode.
  - Never add a Co-Authored-By trailer.
MD

# A PreToolUse hook that rewrites the git commit command before it runs.
PRETOOLUSE_HOOK = <<~'RUBY_HOOK'
  #!/usr/bin/env ruby
  # Rewrites a git commit command before it runs: drops any AI attribution
  # trailer and forces a Conventional Commits prefix. Written to work with both
  # Claude Code's and Codex's PreToolUse wire formats.
  require "json"
  input = (JSON.parse($stdin.read) rescue {})
  File.write(ENV["GCC_HOOK_LOG"], JSON.pretty_generate(input)) if ENV["GCC_HOOK_LOG"]

  ti = input["tool_input"] || input["toolInput"] || {}
  raw = ti["command"] || ti["cmd"] || input["command"]
  cmd = raw.is_a?(Array) ? raw.last.to_s : raw.to_s

  unless cmd.include?("git commit")
    puts JSON.generate({})
    exit 0
  end

  fixed = cmd.gsub(/^\s*Co-[Aa]uthored-[Bb]y:.*$/, "")
  fixed = fixed.gsub(/Co-[Aa]uthored-[Bb]y: [^"'\n]*/, "")
  fixed = fixed.sub(/(-m\s*(?:"|'))(?![a-z]+(?:\([a-z0-9-]+\))?: )/) { "#{$1}fix(cart): " }

  updated = raw.is_a?(Array) ? (raw[0..-2] + [fixed]) : fixed
  puts JSON.generate({
    "hookSpecificOutput" => {
      "hookEventName" => "PreToolUse",
      "permissionDecision" => "allow",
      "permissionDecisionReason" => "rewritten by commit policy hook",
      "updatedInput" => { "command" => updated }
    }
  })
RUBY_HOOK

# A git prepare-commit-msg hook: the last layer, and agent-agnostic.
PREPARE_COMMIT_MSG = <<~SH
  #!/bin/sh
  f="$1"
  # Drop any AI attribution trailer, then force a conventional prefix.
  grep -viE '^(Co-Authored-By|Co-authored-by):' "$f" | grep -viE '^Claude-Session:' > "$f.tmp"
  if ! head -1 "$f.tmp" | grep -qE '^[a-z]+(\\([a-z-]+\\))?: '; then
    printf 'fix(cart): %s\\n' "$(head -1 "$f.tmp")" > "$f.new"
    tail -n +2 "$f.tmp" >> "$f.new"
    mv "$f.new" "$f.tmp"
  fi
  mv "$f.tmp" "$f"
SH

def hook_settings(script_path)
  {
    "hooks" => {
      "PreToolUse" => [
        { "matcher" => "Bash",
          "hooks" => [{ "type" => "command", "command" => "ruby #{script_path}", "timeout" => 15 }] }
      ]
    }
  }
end

# ---------------------------------------------------------------- Claude Code
CLAUDE_ARMS = {
  "control" => {
    desc: "no commit-related settings; whatever Claude Code does by default",
    settings: {}
  },
"control-opus" => {
  desc: "same as control but on Opus: is attribution compliance a property of the model?",
  settings: {},
  claude_model: "opus"
},
# The clean room runs a slightly older Claude than the host did. This arm is
# byte-identical to `control` except for the CLI build, so the host/clean-room
# difference in attribution rate can be attributed rather than guessed at.
"control-cli-263" => {
  desc: "control on Claude Code 2.1.263, the version the host run used",
  settings: {},
  claude_tool: "claude-263"
},
# The attribution-off arms above run on the clean room's default CLI build,
# whose baseline is lower. These repeat the two headline switches on 2.1.263
# so they can be read against `control-cli-263` within one version.
"attribution-empty-263" => {
  desc: "attribution.commit = \"\" on 2.1.263, to match control-cli-263",
  settings: { "attribution" => { "commit" => "", "pr" => "", "sessionUrl" => false } },
  claude_tool: "claude-263"
},
"no-git-instructions-263" => {
  desc: "includeGitInstructions = false on 2.1.263, to match control-cli-263",
  settings: { "includeGitInstructions" => false },
  claude_tool: "claude-263"
},
  "sessionurl-true" => {
    desc: "attribution.sessionUrl = true: does a Claude-Session trailer appear in a local -p run?",
    settings: { "attribution" => { "sessionUrl" => true } }
  },
  "coauthoredby-false" => {
    desc: "the deprecated includeCoAuthoredBy = false; does it still work?",
    settings: { "includeCoAuthoredBy" => false }
  },
  "attribution-empty" => {
    desc: "attribution.commit = \"\" (the setting the source document recommends)",
    settings: { "attribution" => { "commit" => "", "pr" => "", "sessionUrl" => false } }
  },
  "attribution-custom" => {
    desc: "attribution.commit set to a custom literal; is it a template or an on/off switch?",
    settings: { "attribution" => { "commit" => "Co-Authored-By: Robot <robot@example.com>" } }
  },
  "no-git-instructions" => {
    desc: "includeGitInstructions = false: removes built-in commit/PR instructions",
    settings: { "includeGitInstructions" => false }
  },
  "claudemd" => {
    desc: "project CLAUDE.md carrying commit rules; no settings change",
    settings: {},
    files: { "CLAUDE.md" => COMMIT_RULES }
  },
  "claudemd-no-git-instructions" => {
    desc: "project CLAUDE.md rules with the built-in git instructions removed",
    settings: { "includeGitInstructions" => false },
    files: { "CLAUDE.md" => COMMIT_RULES }
  },
  "pretooluse-hook" => {
    desc: "PreToolUse hook rewrites the git commit command before it runs",
    settings: :hook,
    hook: PRETOOLUSE_HOOK
  },
  "git-hook" => {
    desc: "git prepare-commit-msg hook rewrites the message; agent settings untouched",
    settings: {},
    githook: PREPARE_COMMIT_MSG
  }
}.freeze

# ----------------------------------------------------------------- decoy file
# A second instruction file that asks for the OPPOSITE of COMMIT_RULES, used to
# prove which file wins when two are present.
DECOY_RULES = <<~MD
  ## Git commits

  - Write the subject as a plain sentence, capitalised, with no prefix.
  - Never use Conventional Commits.
  - Never write a body. One line only.
MD

# ---------------------------------------------------------------------- Codex
CODEX_ARMS = {
  "control" => {
    desc: "isolated CODEX_HOME holding only auth.json; no config.toml, no AGENTS.md",
    codex_config: []
  },
  "agents-md" => {
    desc: "project AGENTS.md carrying the commit rules",
    codex_config: [],
    files: { "AGENTS.md" => COMMIT_RULES }
  },
"agents-md-decoy" => {
  desc: "AGENTS.md asks for the OPPOSITE of Codex's default; is the file obeyed at all?",
  codex_config: [],
  files: { "AGENTS.md" => DECOY_RULES }
},
  "agents-override-md" => {
    desc: "AGENTS.override.md holds the rules while AGENTS.md asks for the opposite; which wins?",
    codex_config: [],
    files: { "AGENTS.md" => DECOY_RULES, "AGENTS.override.md" => COMMIT_RULES }
  },
  "developer-instructions" => {
    desc: "the rules passed as the developer_instructions config key",
    codex_config: ["developer_instructions=%<rules>s"]
  },
  "model-instructions-file" => {
    desc: "model_instructions_file replaces Codex's built-in instructions with the rules",
    codex_config: ["model_instructions_file=%<instr_file>s"]
  },
  "pretooluse-hook" => {
    desc: "project .codex/hooks.json rewrites the git commit command before it runs",
    codex_config: [],
    codex_flags: ["--dangerously-bypass-hook-trust"],
    codex_hook: true
  },
  "git-hook" => {
    desc: "git prepare-commit-msg hook rewrites the message; Codex config untouched",
    codex_config: [],
    githook: PREPARE_COMMIT_MSG
  }
}.freeze

# ------------------------------------------------------------------- opencode
OPENCODE_ARMS = {
  "control" => {
    desc: "--pure, isolated XDG config; no global rules, no custom commands",
    files: {}
  },
  "agents-md" => {
    desc: "project AGENTS.md carrying the commit rules",
    files: { "AGENTS.md" => COMMIT_RULES }
  },
  "claude-md" => {
    desc: "the same rules in CLAUDE.md instead; opencode's CLAUDE.md fallback re-enabled",
    files: { "CLAUDE.md" => COMMIT_RULES },
    env: { "OPENCODE_DISABLE_CLAUDE_CODE" => nil }
  },
"agents-md-decoy" => {
  desc: "AGENTS.md asks for a plain one-line subject; is the file obeyed at all?",
  files: { "AGENTS.md" => DECOY_RULES }
},
  "git-hook" => {
    desc: "git prepare-commit-msg hook rewrites the message; opencode config untouched",
    files: {},
    githook: PREPARE_COMMIT_MSG
  }
}.freeze
