# GitHub Actions Setup

This guide covers the manual steps required to make the workflows in [`.github/workflows/`](../.github/workflows) fully operational.

## What You Are Configuring

This repository has two workflows:

- [`ci.yml`](../.github/workflows/ci.yml): runs hosted `nix flake check`
- [`vm-smoke.yml`](../.github/workflows/vm-smoke.yml): runs `nix run .#codex-vm-smoke` on a self-hosted KVM runner

The hosted workflow works immediately. The VM smoke workflow requires a self-hosted runner and one repository variable.

## 1. Register A Self-Hosted KVM Runner

1. Open the repository on GitHub.
2. Go to `Settings` > `Actions` > `Runners`.
3. Click `New self-hosted runner`.
4. Choose:
   - Operating system: Linux
   - Architecture: x64
5. Prepare a Linux machine that has:
   - Nix installed
   - KVM available
   - `git` installed
   - permission to access `/dev/kvm`
6. Follow GitHub’s generated runner installation commands on that machine.
7. When configuring labels, make sure the runner has:
   - `self-hosted`
   - `linux`
   - `x64`
   - `kvm`
8. Start the runner service and confirm it appears as `Idle` in the GitHub runners page.

## 2. Enable The VM Smoke Workflow

1. In the repository, go to `Settings` > `Secrets and variables` > `Actions`.
2. Open the `Variables` tab.
3. Create a new repository variable:
   - Name: `ENABLE_SELF_HOSTED_VM_SMOKE`
   - Value: `1`
4. Save the variable.

This enables automatic execution of [`vm-smoke.yml`](../.github/workflows/vm-smoke.yml) on pushes and pull requests. Without this variable, the workflow only runs from `workflow_dispatch`.

## 3. Verify The Setup

1. Push a branch or open a pull request.
2. Confirm `CI / Nix Checks` starts on a GitHub-hosted runner.
3. Confirm `VM Smoke / codex-vm smoke` starts on the self-hosted runner.
4. If needed, trigger `VM Smoke` manually from the `Actions` tab with `Run workflow`.

## 4. Common Failure Checks

- Runner never picks up the job:
  - verify all four labels are present
  - verify the runner is online
- VM smoke job is skipped:
  - verify `ENABLE_SELF_HOSTED_VM_SMOKE=1`
- VM boot fails immediately:
  - verify the runner machine has working KVM access
  - verify the runner user can execute `nix run .#codex-vm-smoke`
