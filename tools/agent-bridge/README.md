# Agent Bridge by CreativTechnik

Agent Bridge is a machine-wide local MCP server for Codex and Claude Code. It
gives both clients the same project-scoped messages, tasks, file claims, Git
overview, rules, and handoff state. A local dashboard can ask both agents the
same question in one chat and request a mutual review.

The bridge does not make one agent the permanent leader. Each implementation
task has an owner, a different reviewer, and an integrator chosen for that task.

## Requirements

- macOS or another local desktop OS
- Node.js 22.13 or newer
- installed and authenticated `codex` and `claude` CLIs for the two-agent chat
- Git for repository status and worktree coordination

The MCP coordination tools still work if only one agent CLI is installed. The
missing agent just cannot be launched from the dashboard.

## Machine-wide installation

From this directory:

```bash
npm install
npm run check
npm pack
npm install --global ./creativtechnik-agent-bridge-0.1.0.tgz
agent-bridge configure
agent-bridge doctor
```

`agent-bridge configure` adds the installed stdio server to Claude Code with
user scope and to the Codex MCP configuration. Existing configurations with the
same name are preserved, not overwritten. It also adds only the ten
`mcp__agent-bridge__*` tools to Claude Code's user-level permission allowlist,
so the coordination tools work without repeated prompts. Other Claude settings
and permissions are preserved. Restart already open Codex and Claude Code
sessions once after the first configuration.

After replacing the globally installed bridge with a newer local build, use
`agent-bridge configure --force` to refresh both client entries. It removes and
recreates only the MCP entry named `agent-bridge`.

## Use in any repository

Open a terminal in the repository:

```bash
agent-bridge init
agent-bridge dashboard
```

`init` creates only missing `AGENTS.md`, `CLAUDE.md`, `AI_RULES.md`, and
`AI_HANDOFF.md` files. Existing files are never overwritten. The generated
`AI_RULES.md` deliberately contains prompts to document verified architecture
and commands instead of inventing repository facts.

The dashboard prints and opens a session-specific URL below
`http://127.0.0.1:47831`. The random path is intentionally different for every
run. To select a different project or port:

```bash
agent-bridge dashboard --root /absolute/path/to/repository --port 47832
```

Other commands:

```bash
agent-bridge status
agent-bridge message "Hinweis für beide Agenten"
agent-bridge doctor
agent-bridge --help
```

## Shared workflow

1. Both agents read the MCP resource `agent-bridge://project/rules`, the handoff
   resource, `bridge_status`, Git status, and existing diffs.
2. A task is created and one agent claims its exact relative file paths.
3. Overlapping active file claims are rejected.
4. The owner implements and submits a concise change and test summary.
5. The other agent approves or requests changes.
6. Either peer may integrate after the foreign review has passed.

Separate Git worktrees are still recommended for simultaneous code changes.
The MCP coordinates intent and state; Git remains the source of truth for code.

## One-chat dashboard

The dashboard can send one message to Codex, Claude, or both. These responses
run in deliberately read-only, non-persistent CLI sessions. The shared project
conversation is supplied to both agents, and the peer-review action asks each
agent to critique the latest response from the other.

Implementation work belongs in the regular Codex or Claude Code session, where
the agent can claim files through MCP and work in a dedicated Git worktree. This
separation prevents a browser chat from silently editing the repository.

## Storage and security

On macOS the shared SQLite state is stored at:

```text
~/Library/Application Support/CreativTechnik/AgentBridge/agent-bridge.sqlite
```

Messages and tasks are separated by the repository's canonical common Git path,
so linked worktrees share the same coordination state. The dashboard binds only
to `127.0.0.1`, uses an unguessable path per process, validates local Host and
Origin headers, and requires a random per-process token for every write request.
The data directory is user-only and the SQLite file is created with user-only
permissions. Agent Bridge does not store API keys or agent credentials.
Authentication remains inside the installed Codex and Claude Code clients.

Set `AGENT_BRIDGE_DATA_DIR`, `AGENT_BRIDGE_DB`, or
`AGENT_BRIDGE_PROJECT_ROOT` only when a custom location or explicit project is
needed.

## Development checks

```bash
npm run check
```

The check covers syntax, database behavior, project-safe initialization,
conflicting file claims, required peer review, MCP tool discovery, MCP resource
reads, and stdio message transport.
