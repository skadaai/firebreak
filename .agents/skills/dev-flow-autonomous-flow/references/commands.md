# Dev Flow Command Examples

Use these as shape references, not rigid templates.

## Reuse The Current Workspace

If the active workspace already belongs to the same spec line, keep working in it and avoid creating another checkout.

## Start A Workspace For A Different Spec

```sh
dev-flow workspace create \
  --workspace-id spec-007-cli \
  --branch agent/spec-007-cli \
  --owner autonomous-operator
```

## Inspect A Workspace

```sh
dev-flow workspace show --workspace-id spec-007-cli
```

## Run Validation

```sh
dev-flow validate run test-smoke-codex-version
```

## Run A Bounded Loop

```sh
dev-flow loop run \
  --workspace-id spec-007-cli \
  --attempt-id rename-skill-surface \
  --spec specs/007-cli-and-naming-contract/SPEC.md \
  --plan "Rename internal skill surface to dev-flow" \
  --validation-suite test-smoke-codex-version \
  --write-path .agents/skills
```
