# Repository Guidelines

## Project Structure & Module Organization

This repository is currently centered on a single Nix flake:

- [`flake.nix`](/home/zvictor/development/microVMs/flake.nix): MicroVM definition, runner packaging, boot-time services, and runtime mount logic.
- [`flake.lock`](/home/zvictor/development/microVMs/flake.lock): pinned inputs.
- [`var.img`](/home/zvictor/development/microVMs/var.img): persistent guest `/var` volume created by the runner.

There is no separate `src/`, `tests/`, or assets tree yet. Keep new logic close to the relevant Nix module unless the file becomes too large, then split into focused `.nix` modules.

## Build, Test, and Development Commands

- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#codex-vm`
  Runs the interactive MicroVM wrapper with dynamic host `PWD` mounting.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' build .#codex-vm-runner`
  Builds the underlying declared runner without launching the VM.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`
  Runs flake evaluation checks. Use this before submitting changes.

## Coding Style & Naming Conventions

Use standard Nix style:

- 2-space indentation.
- Trailing semicolons for attribute assignments.
- Group related options together (`networking`, `users`, `systemd`, `microvm`).
- Prefer descriptive names such as `dev-bootstrap`, `mount-host-cwd`, and `dev-console`.

No formatter is configured in-repo. Keep formatting consistent with existing `flake.nix` structure.

## Testing Guidelines

There is no automated test suite yet. Validate changes by booting the VM and checking the affected behavior directly.

Examples:

- tool bootstrap: `codex --version`
- dynamic path mount: run from a chosen host directory and confirm the same path exists in the guest
- boot flow: confirm the console reaches the `dev` shell without manual login

## Commit & Pull Request Guidelines

Current history uses short imperative commit messages, for example: `add initial codex microvm`. Follow that style.

Pull requests should include:

- a short summary of the behavior change
- exact commands used for validation
- boot logs or console output when changing services, mounts, or login behavior

## Agent-Specific Instructions

Prefer `mcp__deepwiki__ask_question` early when repo behavior is unclear, especially for `microvm.nix` option semantics, runner behavior, or systemd interactions. Use it as a default aid before guessing from memory.
