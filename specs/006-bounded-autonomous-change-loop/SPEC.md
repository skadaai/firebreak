---
status: completed
last_updated: 2026-03-21
---

# 006 Bounded Autonomous Change Loop

## Problem

Firebreak can move toward autonomous development only if the change loop itself is explicit, reviewable, and bounded.

Today, planning, implementation, validation, review, and commit behavior still lives mostly in chat conventions and operator judgment. That is not a strong enough harness for a system that is expected to operate with limited or no per-step human intervention.

Without a defined change loop, autonomy becomes vague: agents can overreach, skip validation, hide uncertainty, or leave behind changes without an auditable reason.

## Affected users, actors, or systems

- autonomous Firebreak coding agents
- parallel worker agents or sub-agents
- maintainers who review or trust autonomous output
- the future Firebreak operator harness that coordinates autonomous work

## Goals

- define the bounded plan, implement, validate, review, and commit loop for autonomous changes
- require evidence before a change is claimed complete
- define when the system may continue independently and when it must stop as blocked
- preserve an audit trail of decisions, validations, and review findings

## Non-goals

- replacing product strategy with autonomous goal setting
- automatic deployment to production
- unlimited retries or unconstrained background operation
- removing human ownership of repository policy

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It defines the agent-facing control loop that sits on top of specs, work tasks, and validation harnesses. The intended landing shape is a bounded autonomous workflow where each substantial change attempt:

- starts from a tracked spec or explicit task contract
- records a plan and current slice
- executes code changes inside an isolated task
- runs required validation suites autonomously
- performs a review pass before commit
- emits a machine-readable audit record
- stops when policy, capability, or evidence requirements are not satisfied

## Requirements

- When an autonomous change attempt begins, the system shall associate that attempt with a tracked spec, explicit task contract, or bounded maintenance action.
- When an autonomous change attempt begins, the system shall record an execution plan or current slice before making substantial code changes.
- When the system completes an implementation slice, the system shall run the required validation suites for that slice without requiring a human to restate them.
- If required validation cannot run because host capabilities or policy requirements are not satisfied, then the system shall stop with a blocked result instead of claiming success.
- If validation fails, then the system shall either retry within a configured budget or stop with a diagnosable blocked result.
- Before creating a commit, the system shall perform a review step focused on regressions, risks, and missing validation.
- If the review step finds unresolved critical issues, then the system shall not mark the change complete or create a misleading success commit.
- When the system creates a commit, the system shall preserve an audit trail containing plan state, validations run, review findings, and resulting disposition.
- While autonomous mode is active, the system shall remain within configured limits for parallelism, runtime, and writable scope.
- If an intended action exceeds configured policy or writable scope, then the system shall stop before taking that action.

## Acceptance criteria

- A bounded autonomous change-loop contract exists with explicit plan, validation, review, and commit stages.
- The contract defines blocked outcomes for missing capability, failed validation, and policy violations.
- The contract requires evidence and review before completion claims or commits.
- Acceptance scenarios exist for a successful bounded change, a validation-blocked change, and a policy-blocked action.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [spec 005](../005-isolated-work-sessions/SPEC.md)
- [AGENTS.md](../../AGENTS.md)

### Risks

- weak stop conditions would let autonomous execution overstate certainty or completion
- a loop that captures no audit trail would make trust impossible to earn or maintain
- trying to encode every future behavior now would produce a bureaucratic system instead of a useful harness

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
