---
status: draft
last_updated: 2026-03-19
---

# 001 Runtime Modularization

## Problem

Firebreak currently mixes guest-runtime behavior and local-launch behavior in the same base module.

That coupling is acceptable for the current local developer workflow, but it makes the next cloud-oriented work harder to reason about because changes to local launch semantics and changes to reusable guest semantics land in the same files and contracts.

## Affected users, actors, or systems

- Firebreak maintainers
- local developers running agent VMs on their own machines
- future remote host runners and orchestrators
- agent-specific overlays that should remain thin

## Goals

- separate reusable guest-runtime behavior from local-launch behavior
- keep the local developer UX intact while refactoring
- create a stable composition model for local and cloud profiles
- make future cloud work additive instead of invasive

## Non-goals

- changing the cloud execution contract itself
- implementing a remote host runner
- changing hypervisors
- changing provider packaging or image publication

## Morphology and scope of the changeset

This changeset is structural.

It will reorganize Firebreak around clearer module boundaries so that:

- guest-common behavior has a stable home
- local-only launch behavior has a stable home
- cloud-only behavior can land without reworking the local path again
- agent overlays such as Codex and Claude Code remain focused on agent-specific concerns

The intended landing shape is a composition model where shared guest logic is reused by multiple profiles rather than duplicated or conditionally inlined across unrelated files.

## Requirements

- The system shall separate reusable guest-runtime behavior from local-launch behavior.
- The system shall express shared behavior in one guest-common contract that can be reused by multiple profiles.
- Where the local-interactive profile is enabled, the system shall preserve the current local Firebreak behavior unless an explicit follow-up spec changes it.
- Where a cloud-oriented profile is enabled, the system shall allow local-only features to be disabled without requiring agent overlays to fork or duplicate shared logic.
- If a future change affects both local and cloud behavior, then the system shall place the shared contract in the guest-common layer rather than duplicate it across profiles.
- The system shall keep agent-specific overlays thin and focused on agent package, config, and environment differences.

## Acceptance criteria

- The repository contains an explicit modular boundary between guest-common behavior and local-launch behavior.
- The local Codex and Claude Code entry points continue to compose from the modularized structure.
- The new modular structure is documented clearly enough that a future change can add cloud behavior without reopening the same architectural split.
- The refactor does not require agent-specific modules to reimplement shared bootstrap or session behavior.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](./engineering/SPECS.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [flake.nix](./flake.nix)
- [module.nix](./modules/base/module.nix)

### Risks

- a premature split could create extra layers without clarifying ownership
- a shallow split could leave local and cloud concerns still coupled under new names
- refactoring module assembly could accidentally change current local behavior if validation is weak

## Relevant constitutional and product docs

- [engineering/SPECS.md](./engineering/SPECS.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
