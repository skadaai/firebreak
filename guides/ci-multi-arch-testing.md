# CI Multi-Arch Testing

This guide records the Firebreak CI policy for architecture coverage and Namespace runner sizing. Keep the workflows aligned with this document.

The source of truth for smoke-package capabilities, supported systems, and per-system shape overrides is [`.github/ci/smoke-tests.json`](../.github/ci/smoke-tests.json). The workflow files must render their matrices from that catalog through [`.github/scripts/render-ci-matrix.sh`](../.github/scripts/render-ci-matrix.sh) rather than carrying their own hand-maintained package lists.

## Goals

- keep one merge-blocking architecture with full confidence
- add representative automated coverage on the other supported host architectures
- avoid the full `architectures x tests` cross-product
- spend the smallest Namespace shape that has actually been proven to work
- keep free GitHub checks ahead of paid Namespace runtime jobs
- keep broad all-arch sweeps out of the pull-request gate

## Supported Host Architectures

Firebreak currently exports public host surfaces for:

- `x86_64-linux`
- `aarch64-linux`
- `aarch64-darwin`

The guest/runtime story is not identical on all of them, so CI should not pretend otherwise.

## Assumptions

- Namespace GitHub Actions runner guarantees are about the runner product, not about bare instances created through `nsc create`.
- Bare-instance probes are still useful for local debugging, but they are not authoritative evidence about what the GitHub runner scheduler path should expose.
- For `aarch64-linux`, missing `/dev/kvm` on a Namespace runner is treated as a runner regression or misconfiguration, not as a permanent Firebreak platform limitation.

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
- representative `aarch64-darwin` host-entry coverage plus Apple Silicon export evaluation

This keeps the most expensive secondary-arch jobs behind both the cheap GitHub gate and the primary runtime gate.

## Scheduled Runs

The enforced scheduled policy is:

- weekly full-arch smoke sweep from `main`

Implementation:

- `Firebreak Namespace Full Arch Sweep` owns the cron trigger
- the scheduled sweep is separate from the pull-request gate
- it runs the broadest practical smoke surface on every supported host architecture

This keeps merge-time CI cost-aware while still giving us a recurring “run everything available” signal outside the PR path.

## Secondary Coverage Rules

Secondary architectures run representative coverage, not the full matrix.

- `aarch64-linux`
  - run a minimal VM-backed smoke to prove the local MicroVM path boots end to end
  - keep one narrow host-surface smoke alongside it
  - do not duplicate the full KVM matrix until we have stable dedicated ARM KVM evidence and capacity
- `aarch64-darwin`
  - run host-entry checks plus Apple Silicon export evaluation
  - do not schedule Linux-guest local runtime smokes on Darwin CI until a compatible Linux guest builder path exists
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

## Namespace Runner Label Policy

Namespace-backed workflows should use runner-label features to reduce cost and queue waste:

- use exactly one `nscloud-*` machine label per job
- attach branch-protected cache volumes shared per architecture
- cache GitHub tool downloads on Namespace runners so `actions/setup-node` does not repeatedly reinstall Node for launcher coverage
- request extra Namespace runner features only where the active runtime path actually needs deeper host access; currently that applies to the `aarch64-linux` local-runtime jobs, which use a combined `-with-cache-with-features` machine label plus `namespace-features:container.privileged=true;container.host-pid-namespace=true`
- on `aarch64-linux`, probe `/dev/kvm` on the actual Namespace runner configuration before fan-out; if KVM is missing, treat that as a Namespace runner regression or misconfiguration and fail explicitly instead of reporting a Firebreak smoke failure

Current cache policy:

- `x86_64-linux` Namespace jobs share `firebreak-runtime-amd64-linux`
- `aarch64-linux` Namespace jobs share `firebreak-runtime-arm64-linux`
- `aarch64-darwin` Namespace jobs share `firebreak-runtime-arm64-darwin`
- only `main` and the repository default branch may persist cache updates

### Current Linux Exceptions

These are the currently documented exceptions to the `1x2` Linux default:

- hosted aggregate `nix flake check`: `2x4`
  - reason: this job evaluates and builds a broad aggregate surface rather than one smoke package
- `firebreak-test-smoke-codex`: `2x4`
  - reason: the full agent cold-boot path regressed below `2x4` in CI; keep it on the first standard step above `1x2`
- `firebreak-test-smoke-codex-version`: `2x4`
  - reason: repeated `1x2` runs were OOM-sensitive in CI
- `firebreak-test-smoke-codex-warm-reuse`: `2x4`
  - reason: repeated `1x2` runs were OOM-sensitive in CI
- `firebreak-test-smoke-claude-code`: `2x4`
  - reason: repeated `1x2` runs were OOM-sensitive in CI
- `firebreak-test-smoke-credential-slots`: `2x4`
  - reason: repeated `1x2` runs were OOM-sensitive in CI
- `firebreak-test-smoke-codex-credential-slots`: `2x4`
  - reason: repeated `1x2` runs were unstable in CI and regressed before completing the workspace-state checks
- `firebreak-test-smoke-claude-code-credential-slots`: `2x4`
  - reason: repeated `1x2` runs were unstable in CI and regressed before completing the workspace-state checks
- `firebreak-test-smoke-internal-task`: `2x4`
  - reason: this smoke is the remaining OOM-sensitive case, so CI keeps it on the first standard step above `1x2`
- `firebreak-test-smoke-port-publish-runtime`: `2x4`
  - reason: repeated `1x2` runs were OOM-sensitive in CI
- `firebreak-test-smoke-worker-claude-version`: `2x4`
  - reason: nested firebreak-backed package resolution was not stable on `1x2`
- `firebreak-test-smoke-worker-guest-bridge`: `2x4`
  - reason: repeated `1x2` runs were OOM-sensitive in CI
- `firebreak-test-smoke-worker-interactive-claude-direct`: `2x4`
  - reason: nested firebreak-backed interactive worker resolution was not stable on `1x2`
- `firebreak-test-smoke-worker-interactive-claude-exit-direct`: `2x4`
  - reason: nested firebreak-backed interactive worker resolution was not stable on `1x2`
- `firebreak-test-smoke-worker-interactive-codex-direct`: `2x4`
  - reason: nested firebreak-backed interactive worker resolution was not stable on `1x2`
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
  - `firebreak-test-smoke-npx-launcher`

### `Firebreak Namespace Full Arch Sweep`

- scheduled weekly on `main`
- broad smoke sweep outside the pull-request gate
- `x86_64-linux`
  - all practical smoke packages, with the same documented Linux shape exceptions
- `aarch64-linux`
  - all practical smoke packages, with the same documented Linux shape exceptions
- `aarch64-darwin`
  - all practical Darwin host-entry smoke packages plus Apple Silicon export evaluation
  - excludes Linux-guest runtime smokes until a compatible Linux guest builder path exists

## CI Catalog Maintenance

When a smoke package is added, removed, or resized:

1. update [`.github/ci/smoke-tests.json`](../.github/ci/smoke-tests.json)
2. update this guide only if policy or a documented shape exception changed
3. do not hand-edit package lists inside workflow files

The catalog entry should define:

- the smoke package name
- the supported host systems for that smoke in CI
- the test features that determine where it belongs, such as whether it requires virtualization or is a representative secondary-arch check
- any per-system shape override beyond the documented defaults

## When Updating CI

When adding or changing a workflow job:

- start from `1x2` on Linux unless there is existing evidence against it
- keep GitHub-only checks separate from Namespace-paid runtime checks
- keep full-matrix runtime coverage on `x86_64-linux`
- add only representative coverage on the secondary architectures
- keep secondary-arch Namespace runtime behind primary-runtime success
- keep the scheduled full sweep separate from merge-time CI
- edit the centralized smoke catalog instead of duplicating package lists in workflow YAML
- update this guide whenever you add or remove a shape exception

## Pitfalls

- Do not append `github.run-id` or `job.priority` inline to the `nscloud-*` machine label. Those are separate runner labels; putting them into the machine label string makes the label invalid.
- Keep Unix domain sockets out of uploaded CI artifact paths. Upload actions may fail with `ENXIO` when they try to archive live `*.socket` files.
- `firebreak-test-smoke-npx-launcher` is intentionally a host-entry smoke. It expects `node` on `PATH` from the workflow environment and should not pull `nodejs` through Nix just to run the smoke.
