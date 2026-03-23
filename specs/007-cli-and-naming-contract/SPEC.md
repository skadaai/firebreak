---
status: in_progress
last_updated: 2026-03-23
---

# 007 CLI And Naming Contract

## Problem

Firebreak's current command and package surfaces mix human-facing entrypoints, agent-only plumbing, and internal test artifacts in one flat namespace.

That causes three forms of confusion:

- top-level `firebreak` subcommands expose internal machinery such as `session`, `validate`, and `autonomy`
- the host-side workspace concept is named `session`, which collides with agent conversation sessions
- test and internal artifact names use inconsistent grammar across CLI arguments, Nix packages, checks, and docs

Without a clear contract, the interface keeps drifting and users have to memorize exceptions instead of learning one naming model.

## Affected users, actors, or systems

- humans using the top-level Firebreak CLI
- coding agents invoking Firebreak internal commands
- maintainers navigating flake outputs and checks
- CI jobs and smoke harnesses consuming Firebreak test packages

## Goals

- separate the human CLI from the internal agent CLI
- rename the host-side isolated work concept from `session` to `task`
- define one naming grammar that works across CLI arguments, Nix packages, checks, docs, and file names
- make test artifacts visibly tests first, instead of normal commands with a trailing suffix

## Non-goals

- implementing full human-facing `init`, `doctor`, or `run` workflows in this changeset
- redesigning guest runtime behavior
- changing agent package names such as `firebreak-codex` and `firebreak-claude-code`
- adding compatibility aliases that preserve every old internal name forever

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It defines the command grammar and naming grammar for Firebreak's exported surfaces.

The intended landing shape is:

- `firebreak` exposes a human-oriented top-level surface
- internal plumbing is routed under `firebreak internal ...`
- the host-side isolated workspace concept is named `task`
- internal packages are prefixed with `firebreak-internal-`
- test packages are prefixed with `firebreak-test-`
- smoke depth appears immediately after `test`

## Requirements

- The system shall reserve the top-level `firebreak` command for human-facing entrypoints and the `internal` subtree.
- When a command primarily exists for agent plumbing or automation, the system shall place it under `firebreak internal ...` instead of the top-level CLI.
- When a host-side isolated work attempt is represented in the CLI, docs, or machine-readable output, the system shall name that concept `task` instead of `session`.
- When Firebreak exports internal plumbing as Nix packages, the system shall prefix those package names with `firebreak-internal-`.
- When Firebreak exports tests as Nix packages or checks, the system shall prefix those names with `firebreak-test-`.
- When Firebreak names a smoke test package or suite, the system shall place `smoke` immediately after `test`.
- The system shall use lowercase hyphenated tokens for package names, CLI suite names, check names, and file names in this changeset.
- The system shall not require `:` or other surface-specific separators for the canonical names introduced by this changeset.
- When the top-level CLI presents help output, the system shall keep internal plumbing out of the human command list except through the `internal` subtree.
- If a human-facing command has no clear user value or intuitive invocation yet, then the system shall keep it unimplemented rather than promoting internal plumbing to the top level.

## Acceptance criteria

- The top-level CLI routes internal plumbing through `firebreak internal ...`.
- The command surface uses `task` where the old interface used `session`.
- Internal package names and test package names follow the new prefixes.
- Smoke packages and suite names use the `test-smoke-...` grammar.
- Checks and docs are updated to the new names.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [spec 005](../005-isolated-work-sessions/SPEC.md)
- [spec 006](../006-bounded-autonomous-change-loop/SPEC.md)

### Risks

- partial renames would leave the interface more confusing than before
- compatibility shims could preserve ambiguous terms such as `session` indefinitely
- moving internal commands without updating checks, docs, and smoke harnesses would create dead surfaces

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
