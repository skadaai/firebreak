# GitHub Actions Setup

This guide covers the manual steps required to make the workflows in [`.github/workflows/`](../.github/workflows) fully operational.

For the enforced CI architecture and Namespace shape policy, see [CI Multi-Arch Testing](./ci-multi-arch-testing.md).

Workflow matrices are generated from [`.github/ci/smoke-tests.json`](../.github/ci/smoke-tests.json) through [`.github/scripts/render-ci-matrix.sh`](../.github/scripts/render-ci-matrix.sh). When changing which smoke packages run in which workflow, update that catalog instead of editing package lists directly in the workflow files.

## What You Are Configuring

This repository has four workflows:

- [`github-fast-checks.yml`](../.github/workflows/github-fast-checks.yml): runs only cheap GitHub-hosted checks
- [`namespace-primary-runtime.yml`](../.github/workflows/namespace-primary-runtime.yml): runs the full paid `x86_64-linux` runtime matrix after the GitHub fast checks pass
- [`namespace-secondary-arch-runtime.yml`](../.github/workflows/namespace-secondary-arch-runtime.yml): runs representative paid secondary-arch runtime checks only after the primary paid runtime gate passes
- [`namespace-full-arch-sweep.yml`](../.github/workflows/namespace-full-arch-sweep.yml): runs the weekly broad multi-arch smoke sweep outside the pull-request gate

The first workflow uses only GitHub-hosted runners. The three Namespace workflows assume the repository can schedule Namespace GitHub Actions runners for the labels used in those workflow files.

The Namespace workflows also use runner-label optimizations:

- branch-protected cache volumes shared per architecture
- GitHub tool caches on Namespace runners for `actions/setup-node`, which keeps launcher coverage from rebuilding Node through Nix on every run

## 1. Enable Namespace GitHub Actions Runners

1. Confirm the repository or organization is connected to Namespace GitHub Actions runners.
2. Confirm jobs can schedule the `nscloud-*` runner labels used by the workflows.
3. Confirm the Linux runners used by the Namespace runtime workflows support the Firebreak Nix workflow with `enable_kvm: true`.
4. Confirm the `aarch64-linux` Namespace jobs can use the combined feature-capable cache runner label form (`nscloud-...-with-cache-with-features`) plus the requested runner feature labels for `container.privileged=true` and `container.host-pid-namespace=true`. Those jobs now request deeper host access because they are meant to exercise the real local Cloud Hypervisor path.
5. Treat `aarch64-darwin` as host-entry coverage plus Apple Silicon export evaluation only for now. Current CI does not provide a Linux guest-builder path for Darwin jobs, so Linux-guest local runtime smokes are intentionally excluded there.
6. The arm64 Linux Namespace workflows now probe `/dev/kvm` before scheduling Cloud Hypervisor smokes. If a Namespace arm64 runner is missing KVM, the workflows fail with an explicit runner-regression message instead of failing inside the guest launcher.

## 2. Verify The Workflow Topology

1. Push a branch or open a pull request.
2. Confirm `Firebreak GitHub Fast Checks` starts automatically.
3. Confirm `Firebreak Namespace Primary Runtime` starts automatically only after the GitHub fast checks finish successfully.
4. Confirm `Firebreak Namespace Secondary Arch Runtime` starts automatically only after the primary Namespace runtime workflow finishes successfully.
5. If needed, trigger any Namespace workflow manually from the `Actions` tab with `Run workflow`.
6. Confirm the weekly scheduled `main` run starts `Firebreak Namespace Full Arch Sweep`.

## 3. Common Failure Checks

- Namespace job never starts:
  - verify Namespace runner integration is active for the repository
  - verify the exact `nscloud-*` labels in the workflow are valid in your Namespace setup
  - verify `job.priority`, `github.run-id`, and similar scheduling controls are separate labels rather than being appended to the `nscloud-*` machine label string
- Namespace primary runtime never starts automatically:
  - verify `Firebreak GitHub Fast Checks` completed successfully
  - verify the workflow name in [`namespace-primary-runtime.yml`](../.github/workflows/namespace-primary-runtime.yml) still matches `Firebreak GitHub Fast Checks`
- Namespace secondary-arch runtime never starts automatically:
  - verify `Firebreak Namespace Primary Runtime` completed successfully
  - verify the workflow name in [`namespace-secondary-arch-runtime.yml`](../.github/workflows/namespace-secondary-arch-runtime.yml) still matches `Firebreak Namespace Primary Runtime`
- Weekly full-arch sweep never starts automatically:
  - verify the cron trigger in [`namespace-full-arch-sweep.yml`](../.github/workflows/namespace-full-arch-sweep.yml) is still present
  - verify scheduled workflows are enabled for the repository
- VM boot fails immediately:
  - verify the Namespace Linux runner can execute KVM-backed Nix workloads
  - verify the runner user can execute `nix run .#firebreak-test-smoke-codex`
- arm64 Linux runtime probe reports missing `/dev/kvm`:
  - treat that as a Namespace runner regression or misconfiguration
  - do not use a bare `nsc create` result as proof that the GitHub runner product lacks KVM
- Launcher smoke unexpectedly asks for `FIREBREAK_WORKLOAD_REGISTRY`:
  - verify the smoke is running from the Firebreak repository root
  - verify the workflow provides `node` on `PATH`, currently through `actions/setup-node`
- Artifact upload fails with `ENXIO` on a socket path:
  - verify the workflow excludes live `*.socket` files from uploaded artifact paths
