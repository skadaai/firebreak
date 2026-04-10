# Role Selection

Use the smallest role that can complete the current phase without taking on extra authority.

## Planner

Use `planner` when the next slice is still being chosen.

Expected output:
- owning spec or maintenance line
- next bounded slice
- workspace decision
- expected validation

Do not use `planner` once implementation has started.

## Worker

Use `worker` when one bounded slice is ready for code changes inside one workspace.

Preconditions:
- owning spec is explicit
- workspace decision is explicit
- expected validation is explicit

Do not use `worker` to coordinate multiple slices or to decide spec ownership.

## Validator

Use `validator` when the slice already exists and the main job is to run or interpret named validation suites.

Do not use `validator` to review risk or pick the slice.

## Reviewer

Use `reviewer` when the diff and validation evidence already exist and the main job is to issue findings.

Do not use `reviewer` to implement or validate.

## Orchestrator

Use `orchestrator` when more than one slice, workspace, or handoff must be coordinated.

Examples:
- sequence two related slices across different specs
- decide when work should return from planner to worker
- coordinate a review or validation handoff across roles

Do not use `orchestrator` for a single bounded slice that a `planner` or `worker` can handle directly.
