---
status: in_progress
last_updated: 2026-04-02
---

# 007 CLI And Naming Contract

## Problem

Firebreak's command and package surfaces still blur together the human-facing product CLI and the automation-oriented development-flow CLI.

That causes four forms of confusion:

- the public `firebreak` CLI has been carrying development-flow plumbing that is not part of the public product experience
- the host-side isolated checkout concept was previously named `task`, which blurred together a workspace and an attempt
- automation workflows need commands that describe development flow rather than Firebreak-exclusive product features
- test and workflow artifact names drift across CLI arguments, Nix packages, checks, and docs

Without a clear contract, the interface keeps drifting and users have to memorize exceptions instead of learning one naming model.

## Affected users, actors, or systems

- humans using the top-level Firebreak CLI
- coding agents invoking Firebreak internal commands
- maintainers navigating flake outputs and checks
- CI jobs and smoke harnesses consuming Firebreak test packages

## Goals

- separate the human CLI from the internal development-flow CLI
- separate attempt terminology from workspace terminology
- define one stable glossary for `tool`, `workload`, `worker`, and `state`
- move development-flow commands to a dedicated `dev-flow` CLI
- define one naming grammar that works across CLI arguments, Nix packages, checks, docs, and file names
- make test artifacts visibly tests first, instead of normal commands with a trailing suffix

## Terminology

- `attempt`: one bounded change attempt with plan, evidence, and disposition
- `workspace`: an isolated host-side checkout with its own worktree, runtime state, artifacts, and metadata
- `tool`: the actual program inside the VM, such as `codex`, `claude`, `aider`, `python`, or `bash`
- `workload`: the Firebreak package or recipe, such as `firebreak-codex` or `firebreak-claude-code`
- `worker`: a running execution instance managed by the broker
- `tool session`: an interactive or non-interactive tool process context launched inside a VM when needed
- `conversation thread`: a tool-specific memory or history object, when the tool exposes one

In this changeset:

- bare `session` must not refer to the host-side work unit
- bare `task` should not be used for the workspace/attempt distinction
- `agent` must not be introduced as a new generic noun in Firebreak core
- `worker` must not be used to mean `tool` or `workload`
- `config` must not be used where the concept is actually persistent runtime `state`

## Non-goals

- implementing full human-facing `init`, `doctor`, or `run` workflows in this changeset
- redesigning guest runtime behavior
- changing existing workload package names such as `firebreak-codex` and `firebreak-claude-code`
- adding compatibility aliases that preserve every old internal name forever

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It defines the command grammar and naming grammar for Firebreak's exported surfaces.

The intended landing shape is:

- `firebreak` exposes a human-oriented top-level surface
- `dev-flow` exposes the automation-oriented workspace, validation, and loop surface
- the host-side isolated checkout concept is named `workspace`
- bounded change execution is named `attempt`
- development-flow packages use `dev-flow` names
- test packages are prefixed with `firebreak-test-`
- smoke depth appears immediately after `test`

## Requirements

- The system shall reserve the top-level `firebreak` command for human-facing entrypoints.
- When a command primarily exists for development-flow plumbing or automation, the system shall place it under the separate `dev-flow` CLI instead of the `firebreak` CLI.
- When a host-side isolated checkout is represented in the CLI, docs, or machine-readable output, the system shall name that concept `workspace`.
- When a bounded change execution is represented in the CLI, docs, or machine-readable output, the system shall name that concept `attempt`.
- When the docs or CLI refer to a VM-contained program, the system shall name that concept `tool`.
- When the docs or CLI refer to a Firebreak package or recipe, the system shall name that concept `workload`.
- When the docs or CLI refer to a broker-managed execution instance, the system shall name that concept `worker`.
- When Firebreak refers to persistent runtime directories, auth material, caches, or related mutable data, the system shall name that concept `state` rather than `config`.
- When Firebreak exports development-flow plumbing as Nix packages, the system shall prefix those package names with `dev-flow-`.
- When Firebreak exports tests as Nix packages or checks, the system shall prefix those names with `firebreak-test-`.
- When Firebreak names a smoke test package or suite, the system shall place `smoke` immediately after `test`.
- The system shall use lowercase hyphenated tokens for package names, CLI suite names, check names, and file names in this changeset.
- The system shall not require `:` or other surface-specific separators for the canonical names introduced by this changeset.
- When the top-level CLI presents help output, the system shall keep development-flow plumbing out of the human command list.
- If a human-facing command has no clear user value or intuitive invocation yet, then the system shall keep it unimplemented rather than promoting internal plumbing to the top level.
- If a legacy file path, env var, template variable, or mount name still contains `agent`, the system shall treat it as migration debt and shall not use it as precedent for new naming.

## Acceptance criteria

- The top-level `firebreak` CLI exposes only the human-facing surface.
- The `dev-flow` CLI exposes workspace, validate, and loop commands.
- The command surface uses `workspace` and `attempt` where the old interface blurred those concepts together.
- Development-flow package names use the `dev-flow-` prefix.
- Smoke packages and suite names use the `test-smoke-...` grammar.
- Checks and docs are updated to the new names and glossary.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [spec 005](../005-isolated-work-tasks/SPEC.md)
- [spec 006](../006-bounded-autonomous-change-loop/SPEC.md)

### Risks

- partial renames would leave the interface more confusing than before
- compatibility shims could preserve ambiguous terms such as `session` indefinitely
- moving internal commands without updating checks, docs, and smoke harnesses would create dead surfaces

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
