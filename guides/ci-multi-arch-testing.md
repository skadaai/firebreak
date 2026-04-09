# CI Multi-Arch Testing

This guide records the Firebreak CI policy for architecture coverage and Namespace runner sizing. Keep the workflows aligned with this document.

## Goals

- keep one merge-blocking architecture with full confidence
- add representative automated coverage on the other supported host architectures
- avoid the full `architectures x tests` cross-product
- spend the smallest Namespace shape that has actually been proven to work
- keep free GitHub checks ahead of paid Namespace runtime jobs

## Supported Host Architectures

Firebreak currently exports public host surfaces for:

- `x86_64-linux`
- `aarch64-linux`
- `aarch64-darwin`

The guest/runtime story is not identical on all of them, so CI should not pretend otherwise.

## CI Policy

### GitHub Fast Gate

`Firebreak GitHub Fast Checks` is the first merge gate.

It runs:

- only GitHub-hosted checks
- cheap fail-fast validation before any paid runtime job starts

### Primary Paid Runtime Gate

`Firebreak Namespace Primary Runtime` is the main paid runtime gate.

It runs:

- the full `x86_64-linux` runtime matrix
- only after the GitHub fast gate passes

### Secondary Paid Runtime Gate

`Firebreak Namespace Secondary Arch Runtime` runs only after the primary paid runtime gate passes.

It runs:

- representative `aarch64-linux` runtime coverage
- representative `aarch64-darwin` `vfkit` coverage

This keeps the most expensive secondary-arch jobs behind both the cheap GitHub gate and the primary runtime gate.

## Secondary Coverage Rules

Secondary architectures run representative coverage, not the full matrix.

- `aarch64-linux`
  - run a minimal VM-backed smoke to prove the local MicroVM path boots end to end
  - keep one narrow host-surface smoke alongside it
  - do not duplicate the full KVM matrix until we have stable dedicated ARM KVM evidence and capacity
- `aarch64-darwin`
  - run a minimal `vfkit`-backed smoke to prove the Apple Silicon local runtime path boots end to end
  - keep narrow output evaluation alongside it
  - do not pretend there is parity with the full Linux KVM matrix

### Escalation Rule

If a change directly touches architecture-sensitive logic, expand only the affected secondary-architecture coverage. Examples:

- launcher and host capability detection
- host packaging and flake output assembly
- Darwin-specific runtime wiring
- ARM-specific host/runtime assumptions

Do not expand all architectures by default.

## Namespace Shape Policy

### Default Rule

Use the smallest available shape first.

- Linux default for single-purpose CI jobs: `1x2`
- macOS default: the smallest available platform-native shape, currently `6x14`

Increase the shape only after a job has shown a concrete need for more resources. When that happens:

1. bump to the smallest shape that is known to pass
2. record the exception in this guide
3. encode the exception directly in the workflow matrix

### Current Linux Exceptions

These are the currently documented exceptions to the `1x2` Linux default:

- hosted aggregate `nix flake check`: `2x4`
  - reason: this job evaluates and builds a broad aggregate surface rather than one smoke package
- `firebreak-test-smoke-internal-task`: `2x4`
  - reason: this smoke is the remaining OOM-sensitive case, so CI keeps it on the first standard step above `1x2`
- `firebreak-test-smoke-worker-guest-bridge-interactive`: `2x4`
  - reason: revalidated on `2x4`; the earlier `4x8` exception was oversized

If a smaller shape is later proven, lower the workflow entry and update this list in the same change.

## Workflow Mapping

### `Firebreak GitHub Fast Checks`

- `x86_64-linux`
  - `nix flake check`
  - full hosted smoke matrix
- no Namespace runner usage

### `Firebreak Namespace Primary Runtime`

- `x86_64-linux` only
- default runner shape per smoke: `1x2`
- exceptions are declared inline in the matrix and mirrored in this guide

### `Firebreak Namespace Secondary Arch Runtime`

- runs only after `Firebreak Namespace Primary Runtime` succeeds
- `aarch64-linux`
  - `firebreak-test-smoke-codex-version`
  - `firebreak-test-smoke-npx-launcher`
- `aarch64-darwin`
  - package/check evaluation for Apple Silicon exports
  - `firebreak-test-smoke-codex-version`
  - `firebreak-test-smoke-npx-launcher`

## When Updating CI

When adding or changing a workflow job:

- start from `1x2` on Linux unless there is existing evidence against it
- keep GitHub-only checks separate from Namespace-paid runtime checks
- keep full-matrix runtime coverage on `x86_64-linux`
- add only representative coverage on the secondary architectures
- keep secondary-arch Namespace runtime behind primary-runtime success
- update this guide whenever you add or remove a shape exception
