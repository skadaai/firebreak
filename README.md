<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-dark.jpg">
    <source media="(prefers-color-scheme: light)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
    <img width="280" alt="Firebreak's logo" src="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
  </picture>
<p>

# Firebreak

Firebreak is a VM-first control plane for running coding agents with a small public interface.

## Firebreak CLI

```sh
firebreak vms
firebreak run codex
firebreak run codex --shell
firebreak run claude-code -- --help
```

`firebreak vms` lists the public VM workloads. `firebreak run <vm>` launches one of them through the existing Firebreak VM packages. The public `firebreak` CLI does not expose agent workflow plumbing.

## dev-flow CLI

Use `dev-flow` for agent-oriented development flow commands such as isolated workspace management, validation, and bounded attempts.

```sh
nix run .#dev-flow -- workspace create --workspace-id spec-005-main --branch agent/spec-005-main
nix run .#dev-flow -- validate run test-smoke-codex
nix run .#dev-flow -- loop run --workspace-id spec-005-main --spec specs/005-isolated-work-tasks/SPEC.md --plan "..." --validation-suite test-smoke-codex-version
```

Use one workspace per spec line. Reuse that workspace for sequential work on the same spec, and start a new workspace when the work moves to a different spec or unrelated maintenance line.

## Agent Workflow

This branch uses a `dev-flow-*` internal skill surface for autonomous work. Start with [dev-flow-autonomous-flow](./.agents/skills/dev-flow-autonomous-flow/SKILL.md), then let it route into the narrower skills for spec selection, workspace choice, boundaries, validation, and review.

The corresponding profile layer under [`.agents/profiles/`](./.agents/profiles) is also aligned to the new names:

- `planner` uses `dev-flow-spec-driving`
- `worker` uses `dev-flow-workspace`, `dev-flow-change-loop`, and `dev-flow-validation`
- `reviewer` uses `dev-flow-review`
- `validator` uses `dev-flow-validation`
- `local-operator` and `cloud-operator` use `dev-flow-runtime-profile`
- `orchestrator` uses `dev-flow-autonomous-flow` for multi-slice coordination

For role-selection guidance and profile preconditions, see [ROLE_SELECTION.md](./.agents/profiles/ROLE_SELECTION.md).

## Local Workloads

- `nix run .#firebreak-codex` launches Codex in the local Firebreak VM
- `nix run .#firebreak-claude-code` launches Claude Code in the local Firebreak VM
- `FIREBREAK_VM_MODE=shell nix run .#firebreak-codex` reaches the maintenance shell for the same VM package
- supported local host systems: `x86_64-linux`, `aarch64-linux`, and Apple Silicon `aarch64-darwin`

## NPX Launcher

Firebreak ships a thin Node launcher so users can run the Nix-backed CLI with `npx firebreak ...`.

```sh
npx firebreak vms
npx firebreak run codex
npx firebreak doctor
npx firebreak init
```

The launcher:

- checks that the host is Linux on `x86_64` or `aarch64`, or Apple Silicon macOS on `arm64`
- checks that `nix` is installed and callable
- checks that `/dev/kvm` is usable before non-diagnostic commands on Linux hosts
- uses the local Firebreak checkout automatically when you run it inside a cloned Firebreak repo
- falls back to `github:skadaai/firebreak` when no local Firebreak checkout is present
- forwards all arguments to the existing Bash Firebreak CLI through `nix run`

Firebreak also ships a thin `npx dev-flow ...` launcher for the agent workflow CLI.

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
- host platform and selected local runtime path
- public VM mode resolution
- Codex and Claude Code config resolution
- current working directory compatibility
- KVM availability when relevant, plus primary-checkout state

Use `nix run .#firebreak -- doctor --json` for machine-readable output.
