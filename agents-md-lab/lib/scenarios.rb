# Each scenario builds a tiny git repo, then says which CANARY tokens each tool
# should see according to the docs (checked on 7 Nov 2026).
#
#   files:     path => content. "{{NAME}}" becomes a unique token like CANARY_NAME_3f9a.
#   cwd:       where the tool is launched, relative to the repo root.
#   claude:    expected tokens for Claude Code, in context order. nil = skip.
#   codex:     expected tokens for Codex, in prompt order. nil = skip.
#   optional:  tokens that may or may not show up without failing the check.
#   claude_mode:  value for Project instructions (pluginConfigs instructionFiles).
#   claude_tools: tools Claude may use. "" = none.
#   claude_task:  what Claude does before listing tokens (for on-demand loading).
#   codex_config: extra -c key=value pairs for Codex.
#   docs:      what the docs say, shown in the report.

FILLER = ("Keep this line as padding so the file is large. " * 20 + "\n")

def big(token_line, kib)
  body = +""
  body << FILLER while body.bytesize < kib * 1024
  token_line + "\n" + body
end

SCENARIOS = [
  {
    name: "agents-only",
    docs: "No CLAUDE files: Claude reads AGENTS.md. Codex reads AGENTS.md.",
    files: { "AGENTS.md" => "Marker {{A_ROOT}}" },
    claude: %w[A_ROOT], codex: %w[A_ROOT]
  },
  {
    name: "claude-and-agents",
    docs: "Both files, no import: Claude reads CLAUDE.md only (default). Codex never reads CLAUDE.md.",
    files: { "CLAUDE.md" => "Marker {{C_ROOT}}", "AGENTS.md" => "Marker {{A_ROOT}}" },
    claude: %w[C_ROOT], codex: %w[A_ROOT]
  },
  {
    name: "claude-imports-agents",
    docs: "CLAUDE.md with @AGENTS.md: Claude reads both, AGENTS.md once, at the import line.",
    files: { "CLAUDE.md" => "@AGENTS.md\n\nMarker {{C_ROOT}}", "AGENTS.md" => "Marker {{A_ROOT}}" },
    claude: %w[A_ROOT C_ROOT], codex: %w[A_ROOT]
  },
  {
    name: "local-turns-agents-off",
    docs: "AGENTS.md + CLAUDE.local.md: CLAUDE.local.md counts, so Claude stops reading AGENTS.md.",
    files: { "AGENTS.md" => "Marker {{A_ROOT}}", "CLAUDE.local.md" => "Marker {{L_ROOT}}" },
    claude: %w[L_ROOT], codex: %w[A_ROOT]
  },
  {
    name: "local-with-and-setting",
    docs: "Same files with Project instructions = claude-md-and-agents-md: CLAUDE files first, then AGENTS.md.",
    files: { "AGENTS.md" => "Marker {{A_ROOT}}", "CLAUDE.local.md" => "Marker {{L_ROOT}}" },
    claude_mode: "claude-md-and-agents-md",
    claude: %w[L_ROOT A_ROOT], codex: nil
  },
  {
    name: "nested-launch-in-subfolder",
    docs: "Launched in app/: both tools read root then app/, closest last.",
    files: { "AGENTS.md" => "Marker {{A_ROOT}}", "app/AGENTS.md" => "Marker {{A_APP}}" },
    cwd: "app",
    claude: %w[A_ROOT A_APP], codex: %w[A_ROOT A_APP]
  },
  {
    name: "dot-claude-agents",
    docs: "Claude also reads .claude/AGENTS.md. Codex does not look in .claude/.",
    files: { ".claude/AGENTS.md" => "Marker {{A_DOTCLAUDE}}" },
    claude: %w[A_DOTCLAUDE], codex: []
  },
  {
    name: "override-file",
    docs: "AGENTS.override.md: Claude ignores it. Codex uses it instead of AGENTS.md.",
    files: { "AGENTS.md" => "Marker {{A_ROOT}}", "AGENTS.override.md" => "Marker {{A_OVERRIDE}}" },
    claude: %w[A_ROOT], codex: %w[A_OVERRIDE]
  },
  {
    name: "agents-local-and-dot-agents",
    docs: "Claude never reads AGENTS.local.md or .agents/. Neither is an AGENTS.md name for Codex.",
    files: {
      "AGENTS.md" => "Marker {{A_ROOT}}",
      "AGENTS.local.md" => "Marker {{A_LOCAL}}",
      ".agents/AGENTS.md" => "Marker {{A_DOTAGENTS}}"
    },
    claude: %w[A_ROOT], codex: %w[A_ROOT]
  },
  {
    name: "import-inside-agents",
    docs: "@path inside AGENTS.md: Claude expands it. Codex has no import syntax.",
    files: { "AGENTS.md" => "Marker {{A_ROOT}}\n\n@docs/style.md", "docs/style.md" => "Marker {{STYLE}}" },
    claude: %w[A_ROOT STYLE], codex: %w[A_ROOT]
  },
  {
    name: "subfolder-on-read",
    docs: "pkg/AGENTS.md loads when Claude opens a file in pkg/ with the Read tool.",
    files: {
      "AGENTS.md" => "Marker {{A_ROOT}}",
      "pkg/AGENTS.md" => "Marker {{A_PKG}}",
      "pkg/thing.rb" => "class Thing; end\n"
    },
    claude_tools: "Read",
    claude_task: "First use the Read tool once to open pkg/thing.rb. Do not open any other file.",
    claude: %w[A_ROOT A_PKG], codex: nil
  },
  {
    name: "subfolder-on-cat",
    docs: "A subfolder AGENTS.md needs the Read tool; a cat through Bash should not load it (CLAUDE.md would load).",
    files: {
      "AGENTS.md" => "Marker {{A_ROOT}}",
      "pkg/AGENTS.md" => "Marker {{A_PKG}}",
      "pkg/thing.rb" => "class Thing; end\n"
    },
    claude_tools: "Bash",
    claude_allow: "Bash(cat pkg/thing.rb)",
    claude_task: "First run exactly this one Bash command: cat pkg/thing.rb. Do not run anything else.",
    claude: %w[A_ROOT], codex: nil
  },
  {
    name: "subfolder-claude-on-cat",
    docs: "Control for subfolder-on-cat: a subfolder CLAUDE.md does load when Claude cats a file there.",
    files: {
      "AGENTS.md" => "Marker {{A_ROOT}}",
      "pkg/CLAUDE.md" => "Marker {{C_PKG}}",
      "pkg/thing.rb" => "class Thing; end\n"
    },
    claude_tools: "Bash",
    claude_allow: "Bash(cat pkg/thing.rb)",
    claude_task: "First run exactly this one Bash command: cat pkg/thing.rb. Do not run anything else.",
    claude: %w[A_ROOT C_PKG], codex: nil
  },
  {
    name: "subfolder-with-own-claude",
    docs: "A subfolder with its own CLAUDE.md: Claude loads that, not the subfolder AGENTS.md.",
    files: {
      "AGENTS.md" => "Marker {{A_ROOT}}",
      "pkg/CLAUDE.md" => "Marker {{C_PKG}}",
      "pkg/AGENTS.md" => "Marker {{A_PKG}}",
      "pkg/thing.rb" => "class Thing; end\n"
    },
    claude_tools: "Read",
    claude_task: "First use the Read tool once to open pkg/thing.rb. Do not open any other file.",
    claude: %w[A_ROOT C_PKG], codex: nil
  },
  {
    name: "codex-fallback-name",
    docs: "TEAM_GUIDE.md is read by Codex only when listed in project_doc_fallback_filenames.",
    files: { "TEAM_GUIDE.md" => "Marker {{TEAM}}" },
    codex_config: ['project_doc_fallback_filenames=["TEAM_GUIDE.md"]'],
    claude: [], codex: %w[TEAM]
  },
  {
    name: "codex-fallback-claude-md",
    docs: "Untested idea from Day 1: list CLAUDE.md as a Codex fallback name so Codex reads it.",
    files: { "CLAUDE.md" => "Marker {{C_ROOT}}\n\n@docs/style.md", "docs/style.md" => "Marker {{STYLE}}" },
    codex_config: ['project_doc_fallback_filenames=["CLAUDE.md"]'],
    claude: nil, codex: %w[C_ROOT]
  },
  {
    name: "codex-size-budget",
    docs: "project_doc_max_bytes (32 KiB) is one budget for the chain: a 20 KiB root file leaves too little for a 20 KiB app/ file.",
    files: {
      "AGENTS.md" => big("Marker {{A_ROOT}}", 20),
      "app/AGENTS.md" => big("Marker {{A_APP_START}}", 20) + "Marker {{A_APP_END}}\n"
    },
    cwd: "app",
    optional: %w[A_APP_START],
    claude: nil, codex: %w[A_ROOT]
  }
].freeze
