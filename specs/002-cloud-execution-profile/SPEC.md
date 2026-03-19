---
status: draft
last_updated: 2026-03-19
---

# 002 Cloud Execution Profile

## Problem

The current Firebreak VM behavior is shaped around a developer launching an agent from their own machine. That includes dynamic host cwd resolution, host identity adoption, and an interactive serial-console workflow.

The cloud use case is different. A remote orchestrator will prepare a workspace and ask Firebreak to run a one-shot coding-agent job with deterministic inputs and outputs. That use case needs a stable guest contract that does not depend on local interactive semantics.

## Affected users, actors, or systems

- remote orchestrators that submit coding-agent jobs
- Firebreak guest VMs running in cloud mode
- maintainers adding future cloud behavior

## Goals

- define a cloud-safe guest execution profile
- keep workspace and config inputs explicit and deterministic
- make one-shot execution the primary cloud interaction model
- capture outputs in a host-visible and testable way

## Non-goals

- multi-host scheduling
- autoscaling
- provider-specific deployment
- interactive cloud shells as a default workflow

## Morphology and scope of the changeset

This changeset is behavioral.

It will define a cloud execution profile over the shared guest runtime. The cloud profile will disable local-only assumptions and provide a fixed contract for:

- workspace mounting
- agent config resolution
- one-shot prompt-driven agent execution
- output persistence
- shutdown behavior

## Requirements

- Where the cloud execution profile is enabled, the system shall mount the guest workspace at a fixed guest path.
- Where the cloud execution profile is enabled, the system shall not require dynamic host cwd metadata to resolve the working directory.
- Where the cloud execution profile is enabled, the system shall not require host uid or gid adoption for the guest development user.
- When a one-shot agent job is requested in the cloud execution profile with an initial prompt, the system shall start a new non-interactive agent session from that prompt without depending on an interactive shell session.
- When a one-shot agent job completes in the cloud execution profile, the system shall persist stdout, stderr, and exit code to host-visible output paths.
- When a one-shot agent job completes in the cloud execution profile, the system shall terminate the VM cleanly after persisting outputs.
- If a required workspace input is absent or unusable, then the system shall fail with a diagnosable non-zero result instead of dropping into an interactive shell.
- While the cloud execution profile is active, the system shall keep interactive console login disabled by default.

## Acceptance criteria

- A cloud-oriented guest profile exists with a defined fixed-path workspace contract.
- The cloud profile does not depend on host cwd metadata or host uid/gid adoption.
- One-shot agent execution is defined as the primary cloud workflow.
- Output persistence and shutdown semantics are explicit and testable.
- Acceptance scenarios exist for successful execution and missing-input failure.

## Dependencies and risks

### Dependencies

- [spec 001](./specs/001-runtime-modularization/SPEC.md)
- [dev-console-start.sh](./modules/base/guest/dev-console-start.sh)
- [prepare-agent-session.sh](./modules/base/guest/prepare-agent-session.sh)

### Risks

- carrying over too much local shell behavior could make the cloud contract ambiguous
- over-constraining the cloud profile could make later artifact or resume flows harder to add
- leaving failure semantics vague would make the host runner harder to automate safely

## Relevant constitutional and product docs

- [engineering/SPECS.md](./engineering/SPECS.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
