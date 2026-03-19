# Upstream Repositories

Use this file as the default map for `mcp__deepwiki__ask_question` when behavior is unclear.

## Core Runtime

| Technology | Upstream repo | Use for |
| --- | --- | --- |
| microvm.nix | `microvm-nix/microvm.nix` | runner behavior, MicroVM options, hypervisor integration |
| Nixpkgs / NixOS modules | `NixOS/nixpkgs` | package names, module options, service behavior |
| QEMU | `qemu/qemu` | hypervisor flags, device behavior, virtiofs/QMP details |
| systemd | `systemd/systemd` | unit ordering, service semantics, shutdown behavior |

## Agent CLIs

| Technology | Upstream repo | Use for |
| --- | --- | --- |
| Codex CLI | `openai/codex` | install/runtime model, config behavior, CLI flags |
| Claude Code | `anthropics/claude-code` | install/runtime model, config behavior, CLI flags |

## Package / Execution Layer

| Technology | Upstream repo | Use for |
| --- | --- | --- |
| Bun | `oven-sh/bun` | `bunx`, cache/temp behavior, package execution, silent flags |

## Usage Notes

- Prefer `ask_question` before guessing when repo behavior is unclear.
- Query the most specific upstream first.
- If the question spans layers, ask the agent CLI repo first, then the runtime/tooling repo.
- Fall back to web search only when the upstream repo is missing the needed answer or the question is not repo-centric.
