---
status: draft
last_updated: 2026-03-19
---

# 003 Remote Job Host

## Problem

After Firebreak has a cloud-safe guest profile, we still need a simple remote host execution path that can launch isolated coding-agent jobs against prepared workspaces without immediately turning into a full control plane.

The first remote step should be a bounded single-host runner that reuses Firebreak's VM boundary and returns deterministic outputs to an orchestrator.

## Affected users, actors, or systems

- remote host operators
- orchestrators that submit coding-agent jobs
- Firebreak guest VMs launched on the remote host

## Goals

- define a single-host remote job runner
- reuse the existing VM boundary instead of switching packaging models
- keep inputs and outputs explicit on the host filesystem
- introduce bounded capacity and runtime guardrails

## Non-goals

- multi-host scheduling
- queue infrastructure
- autoscaling
- provider-specific image publishing
- a generalized storage platform

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It will define a remote host contract that:

- prepares per-job workspace and output directories on the host
- launches a Firebreak VM against those prepared paths
- collects outputs and exit status
- tears down transient runtime state
- enforces simple host-level limits such as capacity and job lifetime

The intent is to prove the remote execution model on one host before adding broader orchestration concerns.

## Requirements

- The system shall provide a remote host job runner that launches a Firebreak VM against host-prepared job inputs.
- When a job is started, the system shall create or resolve isolated host paths for workspace, outputs, and transient runtime state.
- When a job is started with an initial agent prompt, the system shall pass that prompt into a new non-interactive session for the selected agent runtime.
- When a job completes, the system shall persist stdout, stderr, and exit code under the job output path and return the job result to the caller.
- When a job completes or fails, the system shall tear down transient runtime state associated with that job.
- If required job inputs are missing or invalid, then the system shall reject the job before launching the VM.
- If the host capacity limit is exhausted, then the system shall reject the job before launching the VM.
- If a job exceeds the configured runtime limit, then the system shall terminate the VM and surface a diagnosable timeout result.
- While the remote job host contract is active, the system shall not depend on dynamic host cwd resolution or interactive console behavior.

## Acceptance criteria

- A remote single-host Firebreak job contract exists with explicit host paths and VM lifecycle expectations.
- Acceptance scenarios exist for successful execution, input validation failure, capacity rejection, and runtime timeout.
- The remote host contract stays intentionally bounded and does not claim autoscaling or multi-host behavior.

## Dependencies and risks

### Dependencies

- [spec 001](./specs/001-runtime-modularization/SPEC.md)
- [spec 002](./specs/002-cloud-execution-profile/SPEC.md)
- [run-wrapper.sh](./modules/base/host/run-wrapper.sh)

### Risks

- overbuilding the first host runner could turn a bounded execution path into an accidental control plane
- weak capacity and timeout semantics would increase operational risk
- mixing host orchestration concerns back into guest contracts would undo the modular split

## Relevant constitutional and product docs

- [engineering/SPECS.md](./engineering/SPECS.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
