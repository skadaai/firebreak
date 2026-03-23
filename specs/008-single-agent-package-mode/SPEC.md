---
status: in_progress
last_updated: 2026-03-23
---

# 008 Single Agent Package Mode

## Problem

Firebreak currently ships two public local-launch packages per agent:

- a regular package such as `firebreak-codex`
- a shell package such as `firebreak-codex-shell`

Those packages boot the same VM and differ only in the default agent session mode passed into the local wrapper.

That makes the public surface larger than the product behavior actually is, and it teaches users to think in package variants instead of one agent VM with explicit launch modes.

## Affected users, actors, or systems

- humans launching local Firebreak agent VMs
- smoke harnesses validating local interactive and maintenance behavior
- maintainers wiring public Nix package outputs and docs

## Goals

- ship one public local-launch package per agent
- keep shell mode available behind an explicit semantic override
- preserve the default regular agent launch behavior
- update smoke coverage and docs to validate the single-package model

## Non-goals

- introducing a new human-facing CLI flag in this changeset
- changing cloud job packaging or cloud execution behavior
- exposing arbitrary executable paths such as `/bin/bash` as the public contract

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It narrows the public local-launch surface so that each agent ships one public package. That package continues to launch the agent by default, while shell mode remains available as an internal/debug override through the existing semantic mode control.

The intended landing shape is:

- `firebreak-codex` launches Codex by default
- `firebreak-claude-code` launches Claude Code by default
- shell mode is still available through `AGENT_VM_ENTRYPOINT=shell`
- Firebreak no longer exports separate public `*-shell` packages

## Requirements

- The system shall export one public local-launch package per shipped agent VM.
- When a user launches a public local agent package without overrides, the system shall start the default agent mode.
- When a user sets `AGENT_VM_ENTRYPOINT=shell` for a public local agent package, the system shall start the maintenance shell instead of the default agent mode.
- The system shall treat `agent` and `shell` as the public semantic launch modes for this changeset.
- The system shall not require a separate public `*-shell` package to access maintenance shell mode.
- The system shall keep smoke validation for both the default agent mode and the shell override path.
- The system shall update public docs and examples to describe the single-package model.

## Acceptance criteria

- Firebreak exports `firebreak-codex` and `firebreak-claude-code` without separate public `*-shell` siblings.
- Launching a public local package still starts the agent by default.
- Setting `AGENT_VM_ENTRYPOINT=shell` against the same public local package reaches the maintenance shell.
- Local smoke tests validate shell behavior through the same public package rather than a separate shell package.
- Public docs and architecture guidance describe one public package per agent plus the shell override.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [BRANDING.md](../../BRANDING.md)
- [spec 007](../007-cli-and-naming-contract/SPEC.md)

### Risks

- if docs keep referring to `*-shell`, users will keep learning the old interface
- if smoke coverage does not validate the override path, shell mode could silently regress
- if the public contract exposes arbitrary executable paths, the launch interface will become less stable

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [BRANDING.md](../../BRANDING.md)
