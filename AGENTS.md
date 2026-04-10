# Repository Guidelines

## Project Structure & Module Organization

This repository is centered on a Nix flake plus reusable VM modules:

- [`flake.nix`](./flake.nix): top-level flake inputs and output assembly.
- [`nix/flake-support.nix`](./nix/flake-support.nix): shared flake helper builders and rendering helpers.
- [`nix/outputs/`](./nix/outputs): focused flake output assembly for modules, configurations, packages, and checks.
- [`modules/base/`](./modules/base): shared Firebreak VM runtime, with `module.nix`, shared guest-side helpers, and the generic smoke template.
- [`modules/profiles/local/`](./modules/profiles/local): local-launch profile, including local host-side helpers and local guest task-preparation helpers.
- [`modules/profiles/cloud/`](./modules/profiles/cloud): cloud execution profile, including cloud host-side helpers and cloud guest job/task helpers.
- [`modules/packaged-tool/`](./modules/packaged-tool): shared helper layer for image-baked tool CLIs.
- [`modules/codex/`](./modules/codex): Codex-specific overlay module.
- [`modules/claude-code/`](./modules/claude-code): Claude Code-specific overlay module.
- [`ARCHITECTURE.md`](./ARCHITECTURE.md): module-oriented structure and guidance for adding new tool workloads.
- [`BRANDING.md`](./BRANDING.md): product naming, tagline, and public naming conventions.
- [`engineering/TERMINOLOGY.md`](./engineering/TERMINOLOGY.md): canonical glossary for `tool`, `package`, `workload`, `worker`, and `state`.
- [`UPSTREAM_REPOS.md`](./UPSTREAM_REPOS.md): preferred `ask_question` targets for the technologies used in this repository.
- [`guides/`](./guides): step-by-step instructions for tasks that require manual setup or human intervention.
- [`.github/workflows/`](./.github/workflows): hosted CI checks and the self-hosted KVM smoke workflow.
- [`flake.lock`](./flake.lock): pinned inputs.
- VM volume images such as `firebreak-codex-var.img`: persistent guest `/var` volumes created by the runner.

There is no separate application `src/` tree yet. Keep shared behavior in the base module and put tool-specific behavior in focused overlay modules.

## Build, Test, and Development Commands

- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-codex`
  Runs the Codex MicroVM wrapper with dynamic host `PWD` mounting and launches `codex` by default.
- `FIREBREAK_LAUNCH_MODE=shell nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-codex`
  Runs the same Codex MicroVM, but enters the maintenance shell instead of starting `codex`.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-claude-code`
  Runs the Claude Code MicroVM wrapper with dynamic host `PWD` mounting and launches `claude` by default.
- `FIREBREAK_LAUNCH_MODE=shell nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-claude-code`
  Runs the Claude Code VM, but enters the maintenance shell instead of starting `claude`.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-claude-code`
  Runs the lightweight host-side smoke test against the Claude Code VM.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' build .#firebreak-internal-runner-codex`
  Builds the underlying declared runner without launching the VM.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-codex`
  Runs the lightweight host-side smoke test against the interactive Codex VM.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#dev-flow-test-smoke-loop`
  Runs the bounded autonomous change-loop smoke against isolated Firebreak workspaces.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak`
  Runs the top-level Firebreak CLI with the human-facing surface.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`
  Runs flake evaluation checks. Use this before submitting changes.
- `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#dev-flow -- loop run ...`
  Runs the bounded development-flow loop against an existing isolated workspace, recording plan, policy, validation, review, and commit evidence.
- GitHub Actions
  - `.github/workflows/github-fast-checks.yml` runs the hosted fail-fast checks.
  - `.github/workflows/namespace-primary-runtime.yml` runs the primary Namespace runtime matrix after the hosted checks succeed.
  - `.github/workflows/namespace-secondary-arch-runtime.yml` runs representative secondary-architecture runtime coverage after the primary Namespace runtime succeeds.
  - `.github/workflows/namespace-full-arch-sweep.yml` runs the scheduled broader multi-architecture sweep.

## Coding Style & Naming Conventions

Use the canonical terminology in [`engineering/TERMINOLOGY.md`](./engineering/TERMINOLOGY.md).

Naming rules:

- Do not use `agent` as a new generic noun in Firebreak core. Existing `agent-*` identifiers are migration debt, not precedent.
- Do not rename everything to `worker`. `worker` is only for running execution instances.
- Do not use `workload` to mean `package`, or `package` to mean `workload`.
- Do not use `config` when the thing is really persistent runtime state. Prefer `state` and `state root`.
- If a legacy directory, file, or template variable still contains `agent`, treat that as an implementation leftover and avoid propagating it into new interfaces, docs, env vars, or options.

Use standard Nix style:

- 2-space indentation.
- Trailing semicolons for attribute assignments.
- Group related options together (`networking`, `users`, `systemd`, `microvm`).
- Prefer descriptive names such as `dev-bootstrap`, `mount-host-cwd`, and `dev-console`.
- Keep host-side executables under the owning module’s `host/` directory, guest-side executables under `guest/`, and reusable smoke templates under `tests/` inside that module.
- Keep shared guest behavior in `modules/base`, and put launch-environment-specific behavior under `modules/profiles/<profile>/`.

No formatter is configured in-repo. Keep formatting consistent with the existing Nix files under `flake.nix` and `nix/`.

## Testing Guidelines

Use the smoke test for the core runtime path, then boot the VM manually for behavior the smoke test does not cover.

Examples:

- smoke path: `nix run .#firebreak-test-smoke-codex`
- shell entry path: `FIREBREAK_LAUNCH_MODE=shell nix run .#firebreak-codex`
- Claude Code entry path: `nix run .#firebreak-claude-code`
- Claude Code shell path: `FIREBREAK_LAUNCH_MODE=shell nix run .#firebreak-claude-code`
- Claude Code smoke path: `nix run .#firebreak-test-smoke-claude-code`
- tool bootstrap: `codex --version`
- dynamic path mount: run from a chosen host directory and confirm the same path exists in the guest
- boot flow: confirm `nix run .#firebreak-codex` enters `codex`, and `FIREBREAK_LAUNCH_MODE=shell nix run .#firebreak-codex` reaches the `dev` shell
- CI runner note: the VM smoke workflow is gated by the repository variable `ENABLE_SELF_HOSTED_VM_SMOKE=1` so repositories without a KVM runner do not queue indefinitely.
- CI catalog note: whenever a smoke test package is added, removed, renamed, or resized, update [`.github/ci/smoke-tests.json`](./.github/ci/smoke-tests.json) in the same change.

## Commit & Pull Request Guidelines

Current history uses short imperative commit messages, for example: `add initial codex microvm`. Follow that style.

Pull requests should include:

- a short summary of the behavior change
- exact commands used for validation
- boot logs or console output when changing services, mounts, or login behavior

## Agent-Specific Instructions

Prefer `mcp__deepwiki__ask_question` early when behavior is unclear, especially for `microvm.nix` option semantics, runner behavior, or systemd interactions. Use it as a default aid before guessing from memory.

Check [`UPSTREAM_REPOS.md`](./UPSTREAM_REPOS.md) first when choosing which upstream repository to query with `ask_question`.

When running repository tooling inside this sandbox, remember that some standard host tools may be missing from `PATH` even when the skill or helper expects them. For remote Namespace execution specifically, ensure `gnutar` and `gzip` are available locally before running the helper scripts. In this sandbox, the allowed way to provide them is `need inject tar` and `need inject gzip`.

When a change requires manual setup outside the repository, such as configuring GitHub, registering self-hosted runners, adding secrets or variables, or any other human intervention, add or update a detailed step-by-step guide under [`guides/`](./guides) in the same change.

Avoid graceful degradation at all costs; remove all legacy or deprecated code when coding; always prefer fail-fast and KISS; keep the codebase sane, maintainable, and modularized.
