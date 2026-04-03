---
name: dev-flow-review
description: "Use when deciding whether an autonomous change is safe to land. This skill reviews diffs and audit artifacts for regressions, scope escapes, missing evidence, and misleading success claims."
---

# Dev Flow Review

Review findings first. Approval is secondary.

## Inputs

- `diff_artifact_path` (string)
- `validation_summary_path` (string)
- `validation_artifacts` (array of strings)
- `review_artifacts` (array of paths or structured records)

## Outputs

- `findings`
- `blocking_status`
- `evidence_gaps`

## Order

Run review after validation has produced evidence or after the work is explicitly blocked from producing it. Review should consume `diff_artifact_path`, `validation_summary_path`, `validation_artifacts`, and `review_artifacts` for the same workspace-backed attempt.

## Review Pass

1. Check `diff_artifact_path` against the intended slice.
2. Check `validation_summary_path` and `validation_artifacts`.
3. Check `review_artifacts` for conflicts, diff-check issues, and scope violations.
4. Call out real regressions, missing evidence, and policy escapes before summaries.

## Rules

- Treat unresolved critical issues as blocking.
- Do not waive missing validation just because the diff looks clean.
- Do not accept shared-resource changes blindly; verify their resolved target and intent.
- Use `validation_summary_path`, `validation_artifacts`, and `review_artifacts` as the source of truth when they exist.
- Prefer concise findings with exact file references.

## Stop Conditions

- If the diff does not match the intended slice, stop and send it back for re-scoping.
- If review depends on missing validation evidence, stop and report the evidence gap instead of inferring success.
