# Repository Guidelines

## Project Structure & Module Organization

This repository is centered on a Nix flake plus reusable VM modules:

- [`flake.nix`](./flake.nix): flake wiring, VM constructors, packages, and checks.
- [`nix/modules/agent-vm-base.nix`](./nix/modules/agent-vm-base.nix): shared MicroVM base system.
- [`nix/modules/agents/`](./nix/modules/agents): agent-specific overlays such as Codex.
- [`scripts/`](./scripts): runtime wrapper, mount helpers, console startup, and agent bootstrap scripts.
- [`tests/`](./tests): smoke and regression scripts for validating the VM workflow.
- [`guides/`](./guides): step-by-step instructions for tasks that require manual setup or human intervention.
- [`.github/workflows/`](./.github/workflows): hosted CI checks and the self-hosted KVM smoke workflow.
- [`flake.lock`](./flake.lock): pinned inputs.
- [`var.img`](./var.img): persistent guest `/var` volume created by the runner.

There is no separate application `src/` tree yet. Keep shared behavior in the base module and put tool-specific behavior in focused overlay modules.

## Build, Test, and Development Commands

- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#codex-vm`
  Runs the MicroVM wrapper with dynamic host `PWD` mounting and launches `codex` by default.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#codex-vm-shell`
  Runs the same MicroVM, but enters a maintenance shell instead of starting `codex`.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' build .#codex-vm-runner`
  Builds the underlying declared runner without launching the VM.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#codex-vm-smoke`
  Runs the lightweight host-side smoke test against the interactive VM.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`
  Runs flake evaluation checks. Use this before submitting changes.
- GitHub Actions
  - `.github/workflows/ci.yml` runs hosted `flake check` on pushes and pull requests.
  - `.github/workflows/vm-smoke.yml` runs `codex-vm-smoke` on a self-hosted runner labeled `self-hosted`, `linux`, `x64`, and `kvm`.

## Coding Style & Naming Conventions

Use standard Nix style:

- 2-space indentation.
- Trailing semicolons for attribute assignments.
- Group related options together (`networking`, `users`, `systemd`, `microvm`).
- Prefer descriptive names such as `dev-bootstrap`, `mount-host-cwd`, and `dev-console`.

No formatter is configured in-repo. Keep formatting consistent with existing `flake.nix` structure.

## Testing Guidelines

Use the smoke test for the core runtime path, then boot the VM manually for behavior the smoke test does not cover.

Examples:

- smoke path: `nix run .#codex-vm-smoke`
- shell entry path: `nix run .#codex-vm-shell`
- tool bootstrap: `codex --version`
- dynamic path mount: run from a chosen host directory and confirm the same path exists in the guest
- boot flow: confirm `nix run .#codex-vm` enters `codex`, and `nix run .#codex-vm-shell` reaches the `dev` shell
- CI runner note: the VM smoke workflow is gated by the repository variable `ENABLE_SELF_HOSTED_VM_SMOKE=1` so repositories without a KVM runner do not queue indefinitely.

## Commit & Pull Request Guidelines

Current history uses short imperative commit messages, for example: `add initial codex microvm`. Follow that style.

Pull requests should include:

- a short summary of the behavior change
- exact commands used for validation
- boot logs or console output when changing services, mounts, or login behavior

## Agent-Specific Instructions

Prefer `mcp__deepwiki__ask_question` early when repo behavior is unclear, especially for `microvm.nix` option semantics, runner behavior, or systemd interactions. Use it as a default aid before guessing from memory.

When a change requires manual setup outside the repository, such as configuring GitHub, registering self-hosted runners, adding secrets or variables, or any other human intervention, add or update a detailed step-by-step guide under [`guides/`](./guides) in the same change.
