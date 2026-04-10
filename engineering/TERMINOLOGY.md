---
status: canonical
last_updated: 2026-04-10
---

# Terminology

This document is the canonical terminology contract for Firebreak.

If another doc uses a term ambiguously or appears to conflict with this file,
this file wins and the other doc should be updated.

## Core model

- `tool`
  The actual program inside the VM.
  Examples: `codex`, `claude`, `aider`, `python`, `bash`.

- `package`
  A build artifact or installable unit.
  Packages are what Nix builds, caches, and publishes.
  Examples: `firebreak-codex`, `firebreak-claude-code`, `nodejs`.

- `workload`
  A runnable Firebreak execution definition.
  A workload defines how Firebreak launches something: which tool starts, which
  state roots are mounted, which credentials are exposed, and which runtime
  constraints apply.
  A workload is often backed by one or more packages, but it is not the same
  thing as a package.

- `worker`
  A running execution instance managed by the broker.
  Workers are live runtime objects, not package names and not workload
  definitions.

- `state`
  Persistent mutable runtime data.
  This includes tool state, auth material, caches, credentials, and other
  mutable runtime directories.

## Supporting terms

- `workspace`
  An isolated host-side checkout and state root used for one spec line or other
  logically related sequence of work.

- `attempt`
  One bounded change attempt with its own plan, validation evidence, review
  artifacts, and disposition.

- `tool session`
  An interactive or non-interactive tool process context launched inside a VM,
  when that distinction matters.

- `conversation thread`
  A tool-specific memory or history object, when the tool exposes one.

## Relationship between package and workload

Packages and workloads are intentionally different concepts.

- packages are build-time and distribution units
- workloads are runtime launch units

Good shorthand:

- packages are ingredients
- workloads are launch recipes

Examples:

- `firebreak-codex` is a package
- `codex` as launched by `firebreak run codex` is a workload
- a future workload may compose multiple packages
- a future workload may reuse the same package with different state,
  credentials, or runtime constraints

## Naming rules

- Do not introduce `agent` as a new generic noun in Firebreak core.
- Do not use `worker` to mean `tool` or `workload`.
- Do not use `workload` to mean `package`.
- Do not use `config` when the concept is really persistent runtime `state`.
- If a legacy file path, env var, template variable, mount name, or script name
  still contains `agent`, treat that as migration debt rather than precedent.

## Preferred wording by context

- user-facing runtime docs and CLI copy:
  prefer `workload`
- build, cache, artifact, and Nix-output docs:
  prefer `package`
- broker, orchestration, and runtime lifecycle docs:
  prefer `worker`
- persistence, credentials, auth, and mutable directories:
  prefer `state`

When ambiguity matters, say the longer phrase:

- `workload package`
- `workload definition`
- `worker instance`
- `state root`

