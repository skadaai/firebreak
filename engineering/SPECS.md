---
status: canonical
last_updated: 2026-03-19
---

# Specs

## Summary

- meaningful changes should begin with a checked-in spec
- specs are first-class repository artifacts, not external documents
- product-facing specs should use EARS for requirements
- behavioral specs should carry co-located Gherkin acceptance files
- tracked changesets should be organized by scope, not scattered by concern
- specs are for morphology: change-under-definition, change-in-flight, change-landed, and change-still-evolving

## Why this exists

We want feature work to remain:

- trackable
- maintainable
- reviewable
- comparable against implemented behavior

That is much harder when requirements live in chat, tickets, or ad hoc prose.

## The split

### Spec

The spec defines:

- the user and business problem
- the intended behavior
- scope and non-goals
- requirements
- acceptance criteria

### Execution plan

The execution plan defines:

- implementation slices
- sequencing
- dependencies
- validation work
- progress and status

The spec says what must be true.
The plan says how we intend to make it true.

## Requirement style

Product-facing specs should use EARS for requirements where appropriate.

That means requirements should be written in constrained forms such as:

- ubiquitous: `The system shall ...`
- event-driven: `When <event>, the system shall ...`
- state-driven: `While <state>, the system shall ...`
- optional feature: `Where <feature is enabled>, the system shall ...`
- unwanted behavior: `If <condition>, then the system shall ...`

We want requirements that are:

- testable
- unambiguous
- easy for agents to implement
- easy for agents to verify

## Location model

Tracked changesets should live under `./specs`

## Numbering

Spec folders should use a zero-padded numeric prefix:

- `001-environment-hardening`
- `002-vm-bootstrap`

This makes progression visible at a glance and gives stable handles for discussion and retrieval.

## Lifecycle

### 1. Spec first

Substantial changes should not begin with code.
They should begin with a spec.

### 2. Plan second

Once the spec is good enough, add a colocated execution plan.

### 3. Status stays live

Each spec should have a small status file capturing:

- current phase
- what has landed
- what remains open
- what docs or code are authoritative
- a short history of meaningful turns in the changeset

### 4. Keep a stable home while the spec evolves

- a spec should keep the same path while it moves from draft to implementation to lived reality
- a spec should continue tracking the morphology of the system after initial landing when that context still matters
- only abandoned, invalidated, or superseded specs should move to `archived/`

### 5. Treat status as a timeline, not a tombstone

The point of `STATUS.md` is not to declare that work is over forever.

It exists to answer:

- what phase is this changeset in right now?
- what shape has already landed?
- what remains open or has drifted?
- what changed in our understanding over time?

In a living codebase, "implemented" is not the end of thought. It is one phase in the history of a moving system.

## Sync rules

- if implementation changes the meaning of a requirement, update the spec in the same change
- if scope changes materially, update the spec before or with the code
- if the plan changes materially, update the plan in the same change
- if a spec is superseded, archive it explicitly rather than letting it silently rot
- if a shipped system keeps evolving under the same contract, keep the spec live and continue updating its status and history
- if a tracked change belongs to one product, place it in that product's `specs/` folder
- if a tracked change belongs upstream of any single product, place it in `org-specs/`

## Minimum spec contract

Each spec should include:

- problem
- affected users, actors, or systems
- goals
- non-goals
- morphology and scope of the changeset
- EARS requirements where behavior matters
- acceptance criteria
- dependencies and risks
- links to relevant constitutional and product docs

Behavioral specs should also include:

- an `acceptance/` folder with `.feature` files for executable scenarios
- stable scenario tags such as `@spec-004`
- acceptance files that describe intended behavior before implementation begins

Non-behavioral specs do not need Gherkin files when EARS and structural acceptance criteria are sufficient.

## Minimum plan contract

Each plan should include:

- implementation slices
- validation approach
- dependencies
- current status
- open questions

The plan should describe the next intended shape of the work.
It should not pretend the system will stop evolving forever after the first landing.

## Behavioral acceptance model

For user-visible or actor-driven behavior, a spec should not stop at prose acceptance criteria.
It should also provide executable acceptance through co-located `.feature` files.

Recommended layout:

```text
products/<product-slug>/specs/<number>-<slug>/
  SPEC.md
  PLAN.md
  STATUS.md
  acceptance/
    001-happy-path.feature
    002-failure-modes.feature
```

The responsibility split is:

- `SPEC.md` explains the why, scope, contracts, and risks
- `acceptance/*.feature` defines behavior scenarios in executable form
- step definitions stay in the product app's test harness, not in the spec folder

This keeps acceptance truth close to the spec while keeping automation code close to the app.

### When to use Gherkin

Use co-located `.feature` files when the spec covers:

- user-visible behavior
- agent-driven flows
- operational workflows with clear actors and outcomes
- regressions that should become executable acceptance tests

Do not force Gherkin for:

- pure architecture refactors
- internal cleanup
- structural repo work
- implementation slices with no actor-facing behavior

For those cases, EARS in `SPEC.md` remains the right tool.

## Minimum status contract

Each status file should include:

- current phase
- what has landed
- what remains open
- the current sources of truth
- a dated history of meaningful changes in scope, implementation, or understanding

## What good looks like

A future agent should be able to answer:

- why does this spec exist?
- what behavior or system change is required?
- what is already implemented?
- what still remains?
- how has this changeset evolved?
- which code and docs must stay in sync?
- which `.feature` files define the accepted behavior?

without depending on human memory or chat history.
