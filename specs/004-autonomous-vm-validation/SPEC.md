---
status: implemented
last_updated: 2026-03-20
---

# 004 Autonomous VM Validation

## Problem

Firebreak can now boot and validate local and cloud-oriented MicroVM paths, but the validation model is still too dependent on ad hoc human help.

An autonomous Firebreak operator needs a host-resident validation harness that can determine whether VM tests are runnable, execute the right suite without human intervention, and preserve enough evidence for later review.

Without that harness, the project cannot safely move toward a self-directed development loop because agents still depend on humans to decide whether a test environment is valid or to manually relay results.

## Affected users, actors, or systems

- autonomous Firebreak coding agents
- maintainers who review agent-produced changes
- KVM-capable local and CI hosts
- Firebreak VM smoke and job-validation suites

## Goals

- let Firebreak determine on its own whether a host can run VM validation
- provide named validation suites with machine-readable outcomes
- preserve logs and evidence for both successful and failed VM runs
- remove the need for humans to manually rerun VM commands and paste outputs

## Non-goals

- replacing all hosted CI
- introducing distributed scheduling
- designing the full autonomous change loop
- supporting every possible hypervisor or host class in the first version

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It defines a self-service VM validation harness around existing Firebreak packages and checks.

The intended landing shape is:

- a host-side validation entrypoint that can run named Firebreak VM suites
- capability detection that distinguishes runnable, blocked, and failed states
- persisted evidence such as command metadata, exit status, serial output, and suite logs
- a stable contract that later autonomous change loops can call directly

The harness belongs above the VM runtime boundary. It should consume Firebreak runners and smoke packages rather than reimplement VM behavior inside the spec.

## Requirements

- The system shall provide a host-side validation entrypoint for named Firebreak VM suites.
- When a VM validation suite is requested, the system shall determine whether the host satisfies the suite's required capabilities before launching the suite.
- If the host lacks a required capability such as KVM access, then the system shall return a diagnosable blocked result instead of a false test failure.
- When a VM validation suite is launched, the system shall execute it without requiring an interactive human session.
- When a VM validation suite completes, the system shall persist the suite result, exit code, and evidence paths in a machine-readable summary.
- When a VM validation suite emits logs or guest-visible output, the system shall preserve those artifacts under a stable host path for later review.
- Where a validation suite is marked as safe for autonomous use, the system shall provide a non-interactive invocation path that is suitable for autonomous change loops.
- If a validation suite fails before guest evidence is captured, then the system shall still preserve enough host-side output to diagnose the failure.

## Acceptance criteria

- A named VM validation contract exists for Firebreak suites such as local smoke, cloud smoke, and future deeper VM checks.
- Capability detection distinguishes blocked hosts from failing suites.
- Successful and failing suite runs produce machine-readable summaries plus preserved artifacts.
- Acceptance scenarios exist for both runnable and blocked hosts.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [spec 001](../001-runtime-modularization/SPEC.md)
- [spec 002](../002-cloud-execution-profile/SPEC.md)
- [spec 003](../003-remote-job-host/SPEC.md)
- [agent-smoke.sh](../../modules/base/tests/agent-smoke.sh)
- [cloud-smoke.sh](../../modules/profiles/cloud/tests/cloud-smoke.sh)
- [vm-smoke workflow](../../.github/workflows/vm-smoke.yml)

### Risks

- weak capability detection could blur the difference between infrastructure problems and product regressions
- a harness that preserves too little evidence would make autonomous review unreliable
- overfitting the first version to one local machine shape would limit its usefulness in CI and dedicated agent hosts

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
