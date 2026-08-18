  # frozen_string_literal: true

  # The conditions, in one place, because two scripts need them: probe.rb runs
  # them and report.rb labels its rows with them. Keeping the list here means a
  # label corrected after a run is corrected everywhere, instead of surviving in
  # whatever text happened to be written into meta.json at the time.

  # Each condition removes one layer and keeps everything else fixed, so the
  # difference between two rows is the cost of the layer between them.
CONDITIONS = [
  # --- claude ---------------------------------------------------------------
  { agent: "claude", key: "host-full", where: :host, cwd: :neutral, args: [],
    note: "the machine as it is, in a directory with no project files" },
  { agent: "claude", key: "host-project", where: :host, cwd: :project, args: [],
    note: "the same machine, inside a real project" },
  { agent: "claude", key: "host-no-mcp", where: :host, cwd: :neutral,
    args: ["--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}'],
    note: "MCP servers off, everything else on" },
  { agent: "claude", key: "host-no-skills", where: :host, cwd: :neutral,
    args: ["--disable-slash-commands"],
    note: "skills and slash commands off, everything else on" },
  { agent: "claude", key: "host-lean", where: :host, cwd: :neutral,
    args: ["--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--disable-slash-commands"],
    note: "both of the above off together" },
  # There is no flag that turns subagents off. Disallowing the Task tool is the
  # nearest thing, because the catalogue of available subagents is shipped inside
  # that tool's own description. The saving is therefore the tool schema plus the
  # catalogue, and the schema is the small half.
  { agent: "claude", key: "host-no-subagents", where: :host, cwd: :neutral,
    args: ["--disallowed-tools", "Task"],
    note: "the Task tool and the subagent catalogue it carries, off" },
  { agent: "claude", key: "host-leanest", where: :host, cwd: :neutral,
    args: ["--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
           "--disable-slash-commands", "--disallowed-tools", "Task"],
    note: "MCP, skills and subagents all off, hooks and CLAUDE.md still on" },
  { agent: "claude", key: "host-safe-mode", where: :host, cwd: :neutral,
    args: ["--safe-mode"],
    note: "every customisation off: CLAUDE.md, skills, plugins, hooks, MCP, agents" },
  { agent: "claude", key: "host-default-model", where: :host, cwd: :neutral, args: [], model: :default,
    note: "the machine as it is, on whatever model the machine picks by default" },
  { agent: "claude", key: "container", where: :container, cwd: :neutral, args: [],
    note: "a fresh container: a freshly installed CLI and nothing else" },

  # --- codex ----------------------------------------------------------------
  { agent: "codex", key: "host-full", where: :host, cwd: :neutral, args: [],
    note: "the machine as it is, in a directory with no project files" },
  { agent: "codex", key: "host-project", where: :host, cwd: :project, args: [],
    note: "the same machine, inside a real project" },
  { agent: "codex", key: "host-no-config", where: :host, cwd: :neutral,
    args: ["--ignore-user-config"],
    note: "~/.codex/config.toml not read; AGENTS.md and skills still are" },
  { agent: "codex", key: "host-no-mcp", where: :host, cwd: :neutral,
    args: ["-c", "mcp_servers={}"],
    note: "MCP servers off, everything else on" },
  { agent: "codex", key: "container", where: :container, cwd: :neutral, args: [],
    note: "a fresh container: a freshly installed CLI and nothing else" },

  # --- opencode ---------------------------------------------------------------
  #
  # opencode has no --ephemeral and no --no-session-persistence: it writes every
  # run into XDG_DATA_HOME, which is also where its credentials live. So every
  # condition points XDG_DATA_HOME at a private directory seeded with the
  # credential file alone. That keeps runs independent and keeps the probe out of
  # the machine's real session store, and it was checked rather than assumed:
  # against the real data directory the same prompt measured 34,011 tokens and
  # against a private one 33,917, a gap smaller than opencode's own run-to-run
  # spread.
  #
  # The model is pinned like everywhere else. opencode picks its default from
  # state rather than from opencode.json, so a condition that moved the config or
  # the data directory would otherwise be free to pick a different model.
  { agent: "opencode", key: "host-full", where: :host, cwd: :neutral, args: [],
  note: "the machine as it is, in a directory with no project files" },
  { agent: "opencode", key: "host-project", where: :host, cwd: :project, args: [],
  note: "the same machine, inside a real project" },
  { agent: "opencode", key: "host-pure", where: :host, cwd: :neutral,
  args: ["--pure"],
  note: "external plugins off, everything else on" },
  { agent: "opencode", key: "host-no-mcp", where: :host, cwd: :neutral, args: [],
    env: { "XDG_CONFIG_HOME" => :opencode_config_without_mcp },
    note: "MCP servers off, everything else on" },
  # The control for the row above. Taking opencode.json apart to remove the MCP
  # servers also moves XDG_CONFIG_HOME to a temporary path and turns every
  # entry into a symlink, so host-no-mcp differs from host-full in two ways and
  # not one. This condition performs the identical rebuild and leaves the
  # config alone, which separates the two: host-full against this row is the
  # price of the rebuild, and this row against host-no-mcp is the price of MCP.
  { agent: "opencode", key: "host-config-rebuilt", where: :host, cwd: :neutral, args: [],
    env: { "XDG_CONFIG_HOME" => :opencode_config_rebuilt },
    note: "the same rebuilt config directory as host-no-mcp, with the MCP servers left in" },
# And the control for the control. This moves XDG_CONFIG_HOME and changes
# nothing else: one symlink to the real directory, no rewritten JSON, no
# per-entry links. It splits the rebuild's cost into the part that belongs to
# the path and the part that belongs to the surgery.
{ agent: "opencode", key: "host-config-relocated", where: :host, cwd: :neutral, args: [],
  env: { "XDG_CONFIG_HOME" => :opencode_config_relocated },
  note: "the real config directory, reached through a symlink at a temporary path" },
# The relocation again, at a short path instead of a long one. Everything else
# is identical, so the gap between this row and host-config-relocated is the
# cost of the characters in the path and nothing else.
{ agent: "opencode", key: "host-config-short-path", where: :host, cwd: :neutral, args: [],
env: { "XDG_CONFIG_HOME" => :opencode_config_short_path },
note: "the same symlinked config, at a short path instead of a long temporary one" },
  { agent: "opencode", key: "host-no-config", where: :host, cwd: :neutral, args: [],
  env: { "XDG_CONFIG_HOME" => :empty_dir },
  note: "~/.config/opencode not read: no config, skills, agents or commands" },
  { agent: "opencode", key: "host-leanest", where: :host, cwd: :neutral,
  args: ["--pure"], env: { "XDG_CONFIG_HOME" => :empty_dir },
  note: "no config directory and no external plugins" },
  { agent: "opencode", key: "container", where: :container, cwd: :neutral, args: [],
  note: "a fresh container: a freshly installed CLI and nothing else" }
].freeze
