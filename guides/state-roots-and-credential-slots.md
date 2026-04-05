# State Roots And Credential Slots

Firebreak adds isolation and credential switching on top of tools such as Codex and Claude Code.

That is useful, but it can be mentally confusing because the tools already have their own project-level config model.

This guide is the source of truth for the split between native tool behavior, Firebreak-managed state, and Firebreak-managed credentials.

## The three layers

### 1. Native project config

This is whatever the tool already reads from the workspace on its own.

Examples:

- Codex: `.codex/`
- Claude Code: `.claude/`

Firebreak does not try to replace these folders.
If the repo contains them, the tool reads them from the mounted workspace.

### 2. Firebreak runtime state

This is the long-lived state that should be movable or isolatable without rewriting the repo:

- history
- transcripts
- trust state
- caches
- other home-like tool state

Firebreak selects this with the state-mode env vars:

- `FIREBREAK_STATE_MODE`
- `CODEX_STATE_MODE`
- `CLAUDE_STATE_MODE`

Supported modes:

- `host`: shared host-backed runtime state
- `workspace`: runtime state isolated per project
- `vm`: runtime state persisted inside the VM
- `fresh`: runtime state discarded after the launch

### 3. Firebreak credential slots

Credential slots are optional named roots that store auth material separately from runtime state.

Examples:

- `auth.json`
- API-key files
- helper-fed secret files

This lets you keep the same project context and history while switching only the credentials.

Firebreak selects these with:

- `FIREBREAK_CREDENTIAL_SLOT`
- `CODEX_CREDENTIAL_SLOT`
- `CLAUDE_CREDENTIAL_SLOT`

The shared host root defaults to:

- `~/.firebreak/credentials`

Override it with:

- `FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH`

## What `workspace` means

`workspace` does not mean "put all tool state inside `.codex/` or `.claude/` in the repo".

It means:

- keep the tool's native project config in the mounted workspace
- put the tool's Firebreak-managed runtime state in a project-isolated state root outside the repo

This is important because most tools already treat project config as shared behavior config, while auth and long-lived identity state are home-scoped.

## First-run host behavior

For dedicated Firebreak Codex and Claude VMs, `host` mode still tries to adopt existing home config smoothly:

- `~/.codex` can be adopted into `~/.firebreak/codex`
- `~/.claude` can be adopted into `~/.firebreak/claude`

That is only for host-backed runtime state.

It does not change the meaning of native project config in the repo.

## Examples

Use host-backed runtime state and the default credential slot:

```sh
FIREBREAK_STATE_MODE=host \
FIREBREAK_CREDENTIAL_SLOT=default \
nix run .#firebreak-codex
```

Keep the same project-local runtime state but switch only Codex credentials:

```sh
FIREBREAK_STATE_MODE=workspace \
CODEX_CREDENTIAL_SLOT=backup \
nix run .#firebreak-codex
```

Use one default credential slot and override one tool in a multi-tool guest:

```sh
FIREBREAK_CREDENTIAL_SLOT=default \
CLAUDE_CREDENTIAL_SLOT=backup \
FIREBREAK_LAUNCH_MODE=shell \
nix run .#firebreak-agent-orchestrator
```

Inside that guest:

```sh
codex --version
claude --version
```

## Practical rule

When deciding where something belongs:

- if it is native project behavior config, it belongs in the workspace
- if it is long-lived runtime state, it belongs in the selected Firebreak state root
- if it is auth material that you may want to switch independently, it belongs in a credential slot
