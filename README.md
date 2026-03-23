<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-dark.jpg">
    <source media="(prefers-color-scheme: light)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
    <img width="280" alt="Firebreak's logo" src="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
  </picture>
<p>

# Firebreak

Firebreak is a VM-first control plane for running coding agents with a small public interface.

## Local Workloads

- `nix run .#firebreak-codex` launches Codex in the local Firebreak VM
- `nix run .#firebreak-claude-code` launches Claude Code in the local Firebreak VM
- `FIREBREAK_VM_MODE=shell nix run .#firebreak-codex` reaches the maintenance shell for the same VM package

## NPX Launcher

Firebreak ships a thin Node launcher so users can run the Nix-backed CLI with `npx firebreak ...`.

```sh
npx firebreak doctor
npx firebreak init
```

The launcher:

- checks that the host is `x86_64-linux`
- checks that `nix` is installed and callable
- checks that `/dev/kvm` is usable before non-diagnostic commands
- forwards all arguments to the existing Bash Firebreak CLI through `nix run`

## Project Defaults

`firebreak init` is interactive by default and writes a project-local `.firebreak.env` file tailored to the answers you choose. The file uses the same `KEY=VALUE` spelling as the public environment variables, and real environment variables take precedence over file values.

```sh
nix run .#firebreak -- init
nix run .#firebreak -- init --non-interactive
nix run .#firebreak -- doctor
```

Example `.firebreak.env`:

```dotenv
AGENT_CONFIG=workspace
# FIREBREAK_VM_MODE=run
# CODEX_CONFIG=workspace
# CLAUDE_CONFIG=workspace
```

## Diagnostics

`firebreak doctor` reports:

- project root and config-file resolution
- public VM mode resolution
- Codex and Claude Code config resolution
- current working directory compatibility
- KVM availability and primary-checkout state

Use `nix run .#firebreak -- doctor --json` for machine-readable output.
