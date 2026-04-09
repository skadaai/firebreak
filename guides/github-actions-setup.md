# GitHub Actions Setup

This guide covers the manual steps required to make the workflows in [`.github/workflows/`](../.github/workflows) fully operational.

For the enforced CI architecture and Namespace shape policy, see [CI Multi-Arch Testing](./ci-multi-arch-testing.md).

## What You Are Configuring

This repository has two workflows:

- [`hosted-checks.yml`](../.github/workflows/hosted-checks.yml): runs hosted checks on the primary Linux architecture plus representative hosted coverage on the secondary supported architectures
- [`kvm-smoke-tests.yml`](../.github/workflows/kvm-smoke-tests.yml): runs the full KVM-backed smoke matrix on the primary Linux architecture after hosted checks pass

Both workflows assume the repository can schedule Namespace GitHub Actions runners for the labels used in those workflow files.

## 1. Enable Namespace GitHub Actions Runners

1. Confirm the repository or organization is connected to Namespace GitHub Actions runners.
2. Confirm jobs can schedule the `nscloud-*` runner labels used by the workflows.
3. Confirm the Linux runners used by the KVM workflow support the Firebreak Nix workflow with `enable_kvm: true`.

## 2. Verify The Workflow Topology

1. Push a branch or open a pull request.
2. Confirm `Firebreak Hosted Checks` starts automatically.
3. Confirm the hosted workflow fans out into:
   - primary `x86_64-linux` hosted checks
   - representative `aarch64-linux` hosted checks
   - representative `aarch64-darwin` checks
4. Confirm `Firebreak KVM Smoke Tests` starts automatically after the hosted workflow finishes successfully.
5. If needed, trigger `Firebreak KVM Smoke Tests` manually from the `Actions` tab with `Run workflow`.

## 3. Common Failure Checks

- Namespace job never starts:
  - verify Namespace runner integration is active for the repository
  - verify the exact `nscloud-*` labels in the workflow are valid in your Namespace setup
- KVM workflow never starts automatically:
  - verify `Firebreak Hosted Checks` completed successfully
  - verify the workflow name in [`kvm-smoke-tests.yml`](../.github/workflows/kvm-smoke-tests.yml) still matches `Firebreak Hosted Checks`
- VM boot fails immediately:
  - verify the Namespace Linux runner can execute KVM-backed Nix workloads
  - verify the runner user can execute `nix run .#firebreak-test-smoke-codex`
