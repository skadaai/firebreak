---
status: in_progress
last_updated: 2026-03-25
---

# 009 Project Config And Doctor

## Problem

Firebreak is converging on a human-facing control plane, but its user-facing configuration contract is still implicit.

Today, local launch behavior is controlled mostly through environment variables, there is no project-local defaults file, there is no `firebreak init` bootstrap, and there is no `firebreak doctor` command that explains the resolved state before launch.

At the same time, Firebreak also uses many internal environment variables for dev-flow workspace, validation, loop, and cloud-job plumbing. If those are not separated from the user-facing surface, the product contract will drift and users will not know which knobs are stable.

Without a defined config and diagnostics contract, operators have to memorize implementation details, copy shell snippets by hand, and debug launch surprises after the fact instead of before the fact.

## Affected users, actors, or systems

- humans launching local Firebreak workloads
- maintainers documenting and validating the public Firebreak surface
- future human-facing Firebreak commands such as `init` and `doctor`
- local wrapper code that resolves config mode, config paths, and shell versus run mode

## Goals

- define one Firebreak-native project defaults file contract
- keep parity between documented user-facing environment variables and project file keys
- separate public config knobs from internal plumbing variables
- define `firebreak init` as the bootstrap path for project-local defaults
- define `firebreak doctor` as the diagnostics path for resolved Firebreak state
- define precedence between generic and agent-specific config selectors
- make `FIREBREAK_LAUNCH_MODE` the only public local mode selector

## Non-goals

- supporting `.agent-sandbox.env` or other legacy file names as Firebreak config files
- keeping compatibility aliases such as `FIREBREAK_AGENT_MODE` or `AGENT_VM_ENTRYPOINT` as part of the public contract
- exposing dev-flow workspace, validation, loop, or cloud-job plumbing variables as project config controls
- importing old container-runtime, socket, helper, or auth-slot behavior
- defining every future human-facing command beyond the `init` and `doctor` contracts in this changeset

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It defines the human-facing project configuration contract for Firebreak and the corresponding bootstrap and diagnostics commands.

The intended landing shape is:

- Firebreak loads project-local defaults from `.firebreak.env`
- the project file uses the same `KEY=VALUE` spelling as the documented user-facing environment variables
- real environment variables override project file values
- only documented public keys are loaded from the project file
- tool-specific keys such as `CODEX_*` and `CLAUDE_*` override generic `FIREBREAK_*` defaults for their respective workloads
- `host` mode resolves through one shared host root plus stable per-tool subdirectories instead of per-tool host-path variables
- `firebreak init` writes a minimal Firebreak-native defaults file
- `firebreak doctor` explains the resolved config and launch readiness before a workload is started
- `FIREBREAK_LAUNCH_MODE` is the public mode selector for local launch packages

## Requirements

- The system shall resolve the Firebreak project defaults file from `FIREBREAK_PROJECT_CONFIG_FILE` when that variable is set.
- If `FIREBREAK_PROJECT_CONFIG_FILE` is not set, then the system shall resolve the project defaults file from `<project-root>/.firebreak.env`.
- When no project defaults file exists, the system shall continue with built-in defaults instead of failing.
- When Firebreak loads a project defaults file, the system shall parse plain `KEY=VALUE` lines and ignore blank lines and `#` comments.
- When both a real environment variable and the project defaults file define the same supported key, the system shall give precedence to the real environment variable.
- When the project defaults file contains an unsupported key, the system shall ignore that key rather than treating it as part of the public Firebreak config contract.
- The system shall define an allowlist of documented user-facing keys that may be loaded from the project defaults file.
- The system shall not treat internal plumbing variables for dev-flow workspace, validation, loop, or cloud-job execution as part of the project defaults contract.
- When resolving local workload state for Codex, the system shall give precedence to `CODEX_*` selectors over generic `FIREBREAK_*` defaults for Codex-specific behavior.
- When resolving local workload state for Claude Code, the system shall give precedence to `CLAUDE_*` selectors over generic `FIREBREAK_*` defaults for Claude-specific behavior.
- The system shall use `host`, `workspace`, `vm`, and `fresh` as the public state-mode vocabulary for local workload state resolution.
- When Firebreak resolves local workload state in `host` mode, the system shall treat `FIREBREAK_STATE_ROOT` as one shared host state root rather than a per-tool leaf directory.
- When Firebreak resolves Codex state in `host` mode, the system shall map that resolution to a stable `codex` subdirectory within the shared host state root.
- When Firebreak resolves Claude Code state in `host` mode, the system shall map that resolution to a stable `claude` subdirectory within the shared host state root.
- The system shall not require or document `CODEX_CONFIG_HOST_PATH` or `CLAUDE_CONFIG_HOST_PATH` as part of the public local config contract.
- The system shall provide `firebreak init` to write a Firebreak-native project defaults template.
- When `firebreak init` writes the project defaults template, the system shall use `.firebreak.env` instead of a legacy sandbox file name.
- When `firebreak init` writes the project defaults template, the system shall keep that template minimal and focused on the stable public Firebreak knobs.
- The system shall provide `firebreak doctor` to report the resolved project root, project config source, local mode resolution, tool state resolution, and host readiness before launch.
- When `firebreak doctor` reports host readiness, the system shall include whether KVM is readable and writable on the host.
- When `firebreak doctor` reports local launch readiness, the system shall include whether the current working directory is compatible with Firebreak's mount and runtime path assumptions.
- Where `firebreak doctor --json` is requested, the system shall emit machine-readable diagnostics.
- Where `firebreak doctor --verbose` is requested, the system shall emit expanded diagnostics instead of only a short summary.
- The system shall use `FIREBREAK_LAUNCH_MODE` as the documented public mode selector for local workload packages.
- The system shall not require or document `FIREBREAK_AGENT_MODE` or `AGENT_VM_ENTRYPOINT` as public compatibility aliases once this contract lands.

## Acceptance criteria

- `.firebreak.env` is the Firebreak project defaults file and uses `KEY=VALUE` entries.
- Supported public settings can be expressed the same way in the process environment and in the project defaults file.
- Unsupported internal plumbing variables are excluded from the project defaults contract.
- Tool-specific selectors override generic defaults for their matching workloads.
- `host` mode resolves through one shared host root with stable per-tool subdirectories.
- `firebreak init` emits a Firebreak-native minimal template.
- `firebreak doctor` can explain the resolved config and readiness state before launch.
- `FIREBREAK_LAUNCH_MODE` is the public local mode selector, and legacy mode aliases are removed from the public contract.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [spec 007](../007-cli-and-naming-contract/SPEC.md)
- [spec 008](../008-single-agent-package-mode/SPEC.md)

### Risks

- if the config allowlist is too broad, internal implementation details will harden into public contract
- if the config allowlist is too narrow, users will fall back to undocumented shell conventions
- if Firebreak keeps legacy mode aliases in the public contract, the surface will accumulate migration baggage instead of converging
- if `doctor` omits the most important readiness checks, users will still have to debug failures after launch

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
