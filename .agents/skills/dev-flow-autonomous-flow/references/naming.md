# Workspace And Branch Naming

Use short, stable identifiers that communicate the owning spec or maintenance line.

## Preferred Shapes

- Spec-backed workspace ID: `spec-007-cli`
- Spec-backed branch: `agent/spec-007-cli`
- Maintenance workspace ID: `maintenance-shellcheck`
- Maintenance branch: `agent/maintenance-shellcheck`

## Rules

- Prefer the owning spec number or a short maintenance label.
- Keep the workspace ID stable while the same spec line continues.
- Do not create a new ID for every slice, file, or validation run.
- Keep branch names aligned with workspace IDs when possible.
