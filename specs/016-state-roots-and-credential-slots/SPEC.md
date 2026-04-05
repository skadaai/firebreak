---
status: draft
last_updated: 2026-04-04
---

# 016 State Roots And Credential Slots

## Problem

Firebreak currently treats state-mode selection as if one resolved directory can stand in for the full runtime state of a tool.

That was sufficient while Firebreak only needed to choose between `host`, `workspace`, `vm`, and `fresh` paths for a single agent-shaped config root.

It breaks down once Firebreak tries to support both:

- native project-scoped config that tools already load from the mounted workspace
- Firebreak-managed switching of credentials and long-lived runtime state

Modern coding tools already distinguish project behavior config from home-scoped identity and session state.

Examples include:

- Codex reading project config from `.codex/` while keeping `auth.json`, transcripts, and other long-lived state under `~/.codex/`
- Claude Code reading project config from `.claude/` while keeping login and other user identity state outside that project folder

Firebreak's current model risks colliding with those native expectations by making `workspace` behave like a Firebreak-managed project config root instead of letting the tool's own project config come from the mounted working tree.

At the same time, users still want Firebreak-specific value that the tools do not provide natively:

- switch credentials quickly when one subscription or API key is exhausted
- keep working on the same project with as little disturbance as possible
- isolate long-lived tool state per project, VM, or fresh session without rewriting the project's native config files

Without a clearer contract, Firebreak mixes three separate concerns:

- native project config loaded from the workspace
- runtime state such as history, trust, transcripts, and caches
- credentials such as OAuth tokens, `auth.json`, API keys, and helper-driven token retrieval

## Affected users, actors, or systems

- humans launching Firebreak-packaged tools such as Codex and Claude Code
- external Firebreak recipes that install more than one tool in one guest
- future non-agent Firebreak workloads that still need state or credential injection
- Firebreak runtime modules that resolve config/state paths and materialize host mounts
- package authors who want Firebreak to help with credential switching without forcing a global abstraction on every program

## Goals

- separate native project config from Firebreak-managed runtime state
- redefine Firebreak's mode selection around runtime state roots rather than around fake project-config roots
- let tools keep using their native project-scoped config directly from the mounted workspace
- preserve Firebreak-specific value for switching credentials with minimal disturbance to active work
- make credential injection an opt-in package capability rather than a mandatory global abstraction
- support more than one credential slot in the same guest, including per-tool overrides for multi-tool workloads
- support native login flows by materializing the selected credential slot at the path the tool naturally writes to
- keep the first contract small and generic enough to support future non-agent programs
- document the resulting state-root and credential-slot model in user-friendly language that explains where Firebreak intentionally differs from each tool's native behavior

## Non-goals

- redefining each tool's native project config schema
- inventing a Firebreak-only replacement for `.codex/`, `.claude/`, or other project folders
- forcing every Firebreak package to support credential switching
- requiring post-login file watching and capture as the primary credential-management mechanism
- standardizing every provider-specific login experience behind one fake universal login command
- solving every platform-specific credential store in the first changeset

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It introduces a cleaner contract for how Firebreak supplies runtime state and optional credentials to packaged tools.

The intended landing shape is:

- Firebreak leaves native project-scoped config to the mounted workspace
- Firebreak's `host`, `workspace`, `vm`, and `fresh` modes select the runtime state root rather than pretending to be the project's config root
- Firebreak can optionally expose named credential slots
- packages may opt into one or more credential adapters
- each credential adapter defines how a selected slot is materialized into the path, env var, or helper command that the packaged tool naturally expects
- where a tool offers a native login flow, Firebreak can run that flow against the selected slot by materializing the slot at the natural runtime path before login starts

## Requirements

- The system shall treat native project-scoped tool config as part of the mounted workspace rather than as part of Firebreak-managed runtime state.
- The system shall not require Firebreak to create or overlay a fake `.codex/`, `.claude/`, or equivalent project folder as part of the runtime-state contract.
- The system shall redefine Firebreak's state-selection modes so `host`, `workspace`, `vm`, and `fresh` govern the runtime state root rather than the native project config root.
- When a tool runs in `workspace` mode, the system shall keep that tool's runtime state isolated per project while still allowing the tool to read its native project config from the mounted working tree.
- When a tool runs in `host` mode, the system shall allow the tool to use a host-backed runtime state root without suppressing native project config from the mounted working tree.
- When a tool runs in `vm` mode, the system shall keep runtime state persistent inside the VM while still allowing native project config from the mounted working tree.
- When a tool runs in `fresh` mode, the system shall keep runtime state ephemeral while still allowing native project config from the mounted working tree.
- The system shall make credential injection an opt-in package capability.
- The system shall allow a package to declare one or more credential adapters rather than assuming all packages understand the same credential contract.
- The system shall support at least three generic credential-adapter primitives: file materialization, env-var injection, and helper-command generation.
- The system shall allow a package to declare a native login command for a credential adapter when the packaged tool supports a login flow.
- When a package declares a native login command, the system shall be able to materialize the selected credential slot at the path the tool naturally expects before that login command runs.
- The system shall prefer slot-first native login materialization over post-login capture as the primary credential-management path.
- The system shall allow a default credential slot plus per-tool overrides inside the same guest.
- The system shall not require switching the runtime state root merely to switch credentials.
- The system shall support workloads that need more than one credential slot at the same time, such as multi-tool orchestration sandboxes.
- The system shall allow a package to declare no credential adapters at all without changing its behavior.
- The system shall not require non-agent programs to participate in Firebreak credential-slot semantics unless their package explicitly opts in.
- The system shall document state roots, native project config, and credential slots in a way that is explicit about the difference between Firebreak behavior and each packaged tool's native config model.
- The system shall provide user-facing examples for common flows such as native project config usage, workspace-isolated state, and slot-based credential switching.

## Recorded decisions

- Firebreak should manage runtime state and credentials separately. Credential switching and state isolation are different axes.
- `workspace` should mean project-isolated runtime state, not Firebreak-managed project config.
- Native project config should continue to come from the mounted workspace.
- Firebreak credential switching should not be modeled as whole-profile switching when the user only needs to replace exhausted credentials and keep the same working context.
- Credential slots should remain simple named storage roots, with package adapters deciding which files or env vars they consume.
- Packages should declare how credentials are injected. Firebreak core should provide generic materialization primitives rather than tool-specific hardcoding everywhere.
- Native login flows should write directly into the selected slot when possible by materializing the slot at the path the tool naturally writes to.

## Acceptance criteria

- Firebreak can run a packaged tool with native project config coming from the mounted workspace while runtime state is selected independently through `host`, `workspace`, `vm`, or `fresh`.
- `workspace` mode isolates runtime state per project without requiring Firebreak to create or own the tool's native project config folder.
- A package can opt into credential-slot support by declaring adapters, and a package that declares none keeps its prior behavior.
- Firebreak can choose one default credential slot and also override that choice for a specific tool in the same guest.
- At least one file-based native login flow can write directly into a selected credential slot through slot-first materialization rather than post-login file capture.
- At least one env-driven credential flow can read a value from a selected slot and expose it through the env var the packaged tool naturally expects.
- At least one helper-driven credential flow can read from a selected slot through a Firebreak-generated helper command or script.
- User-facing documentation explains the model clearly enough that operators can distinguish native project config from Firebreak-managed state and credentials without needing to infer the distinction from implementation details.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [spec 009](../009-project-config-and-doctor/SPEC.md)
- [spec 014](../014-multi-agent-host-config-share/SPEC.md)
- current [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- current [modules/base/guest/resolve-state-root.sh](../../modules/base/guest/resolve-state-root.sh)

### Risks

- if Firebreak keeps conflating native project config with runtime state, it will continue to violate the expectations of packaged tools
- if credential injection is too global, Firebreak will impose agent-specific assumptions on unrelated programs
- if slot materialization is underspecified, package authors will reintroduce ad hoc wrapper logic instead of using the shared model
- if native login materialization is not robust enough, packages may fall back to fragile capture-after-login flows
- if state-mode defaults and credential-slot defaults are not clearly documented, users will not be able to predict which identity and which history they are carrying into a new session

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [README.md](../../README.md)
