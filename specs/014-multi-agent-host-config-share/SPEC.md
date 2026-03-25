---
status: in_progress
last_updated: 2026-03-25
---

# 014 Multi-Agent Host Config Share

## Problem

Firebreak's current host-backed agent config contract is single-agent-shaped.

A normal Firebreak workload resolves one effective agent config directory for one tool inside one VM. That works for dedicated workloads such as Codex or Claude Code, but it does not fit multi-agent sandboxes such as agent orchestrators that need more than one agent CLI in the same guest at the same time.

Without a multi-agent host config share, a sandbox that installs both `codex` and `claude` must either:

- ignore Firebreak's config selectors and fall back to ad hoc shell conventions
- treat one tool's config directory as if it belonged to all tools
- or require separate Firebreak VMs instead of one shared orchestration sandbox

That leaves Firebreak's public config contract incomplete for an important class of workloads.

## Affected users, actors, or systems

- humans launching multi-agent Firebreak sandboxes
- external sandbox recipes that install more than one agent CLI in one VM
- wrapper commands that translate Firebreak config selectors into agent-native environment variables
- future orchestrator-style workloads built on Firebreak's packaged Node CLI layer

## Goals

- define a Firebreak-native host config contract for multi-agent sandboxes
- keep the existing single-agent host config contract intact for dedicated workloads
- let one sandbox expose multiple agent CLIs while still respecting Firebreak config selectors
- provide one mounted host config root with stable per-agent subdirectories
- preserve precedence between generic and agent-specific selectors
- let Firebreak wrappers translate the resolved directories into agent-native env vars such as `CODEX_HOME`, `CODEX_CONFIG_DIR`, and `CLAUDE_CONFIG_DIR`

## Non-goals

- nested MicroVMs or guest-launched child VMs
- redesigning Firebreak around an orchestrator scheduler in this changeset
- forcing all multi-agent sandboxes to use host-backed config mode
- changing the dedicated single-agent workload contract for `firebreak-codex` or `firebreak-claude-code`
- defining every future multi-agent sandbox wrapper in this spec

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It defines how Firebreak exposes host-backed config directories to sandboxes that contain more than one agent CLI.

The intended landing shape is:

- Firebreak can mount one host-backed config root into a multi-agent sandbox
- each shipped agent inside that sandbox receives a stable subdirectory within that mounted root
- generic selectors such as `AGENT_CONFIG` remain available as shared defaults
- agent-specific selectors such as `CODEX_CONFIG` and `CLAUDE_CONFIG` continue to override the generic selector for their matching tools
- Firebreak-provided wrapper commands translate the resolved Firebreak config location into the env vars the agent CLI actually understands
- dedicated single-agent workloads keep their existing single-directory host config behavior
- the first public contract stays small: one shared host root, fixed per-agent subdirectories, and per-agent mode overrides without per-agent host-path overrides

## Requirements

- The system shall provide an optional multi-agent host config share contract for sandboxes that expose more than one agent CLI in one guest.
- Where a sandbox enables the multi-agent host config share contract, the system shall mount one host-backed config root into that guest instead of requiring one independent host share per agent.
- Where a sandbox enables the multi-agent host config share contract, the system shall resolve stable per-agent subdirectories inside that mounted host root.
- The system shall keep the single-agent host config contract for dedicated Firebreak workloads unchanged.
- When a multi-agent sandbox resolves Codex config in `host` mode, the system shall map that resolution to the Codex subdirectory within the mounted host config root.
- When a multi-agent sandbox resolves Claude Code config in `host` mode, the system shall map that resolution to the Claude subdirectory within the mounted host config root.
- When both a generic selector and an agent-specific selector are present, the system shall give precedence to the agent-specific selector for that matching tool.
- When a multi-agent sandbox launches Codex through the Firebreak wrapper, the system shall export the resolved directory through Codex-native env vars rather than expecting Codex to understand Firebreak selector vars directly.
- When a multi-agent sandbox launches Claude Code through the Firebreak wrapper, the system shall export the resolved directory through Claude-native env vars rather than expecting Claude Code to understand Firebreak selector vars directly.
- The system shall support `workspace`, `vm`, and `fresh` modes for wrappers in the same way as the existing Firebreak config contract.
- Where `host` mode is enabled for a multi-agent sandbox, the system shall expose enough mounted host state for multiple agent wrappers to resolve distinct host-backed directories in the same guest.
- The system shall not require one tool's host config directory to be reused as another tool's host config directory as part of the public contract.
- The system shall document the stable subdirectory naming rules for each shipped agent made available through the multi-agent host config share.

## Acceptance criteria

- a multi-agent Firebreak sandbox can expose both Codex and Claude Code while keeping separate resolved config directories for each
- `AGENT_CONFIG` still acts as the generic default selector in a multi-agent sandbox
- `CODEX_CONFIG` and `CLAUDE_CONFIG` still override the generic selector for their matching wrappers
- `host` mode can be expressed as one mounted host root plus per-agent subdirectories instead of one shared leaf directory for all tools
- Firebreak wrappers export agent-native config env vars so the installed agent CLIs use the resolved directories without understanding Firebreak selector vars directly

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [spec 009](../009-project-config-and-doctor/SPEC.md)
- current packaged Node CLI layer in [modules/node-cli/module.nix](../../modules/node-cli/module.nix)
- current single-agent local wrapper contract in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)

### Risks

- if the host-root contract is underspecified, different multi-agent sandboxes will invent incompatible directory layouts
- if the generic and per-agent precedence rules drift from spec 009, users will not be able to predict which config directory a wrapper will use
- if Firebreak does not provide wrappers, maintainers will keep re-implementing agent-specific env translation in ad hoc ways
- if the contract mutates the existing single-agent host config semantics, dedicated workloads may regress while multi-agent support lands

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)
