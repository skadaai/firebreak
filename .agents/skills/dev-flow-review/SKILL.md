---
name: dev-flow-review
description: "Use when deciding whether an autonomous change is safe to land. This skill reviews diffs and audit artifacts for regressions, scope escapes, missing evidence, and misleading success claims."
---

# Dev Flow Review

Review findings first. Approval is secondary.

## Order

Run review after validation has produced evidence or after the work is explicitly blocked from producing it. Review should consume the recorded diff, validation summary, and any review artifacts for the same workspace-backed attempt.

## Review Pass

1. Check the changed files against the intended slice.
2. Check validation results and artifact paths.
3. Check review artifacts for conflicts, diff-check issues, and scope violations.
4. Call out real regressions, missing evidence, and policy escapes before summaries.

## Rules

- Treat unresolved critical issues as blocking.
- Do not waive missing validation just because the diff looks clean.
- Do not accept shared-resource changes blindly; verify their resolved target and intent.
- Use the recorded validation and review artifacts as the source of truth when they exist.
- Prefer concise findings with exact file references.
