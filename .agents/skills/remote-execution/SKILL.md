---
name: remote-execution
description: >
  Run tests or heavy computations on ephemeral Namespace.so compute instances.
  Use this skill when a test requires /dev/kvm, firecracker, nested virtualization,
  or any NixOS VM-level isolation. Handles full instance lifecycle transparently:
  provision → upload workspace → run → stream logs → destroy.
  Do NOT use for tests that can run locally without KVM. Do NOT create Devboxes.
---

# Remote Namespace.so Execution

## When to use

- The user asks to run tests remotely or in a clean isolated environment.
- The local environment is not Linux or does not support nested virtualization, but the test requires it.
- Local execution would fail due to missing `/dev/kvm`.
- The local environment is already waiting on more than 4 long-running background processes.
- The local environment is too slow or unstable for the test, and a remote instance would be more reliable.
- The local environment has insufficient resources (CPU, RAM) to run the test effectively, and a remote instance would provide better performance.
- The local environment is overloaded with other tasks, and running the test remotely would free up resources and reduce interference.

## When NOT to use

- Tests that do not require KVM or virtualization.
- The user asks to open, explore, or iteratively develop in a devbox.
- The user asks to run a quick test that can easily run locally without KVM.
- The user asks to run a test that is already running locally without issues.
- The local environment is stable, responsive, and has sufficient resources to run the test effectively.
- The user asks to run a test that is not resource-intensive and does not require isolation.

## Required environment variables

Read `references/env.md` before invoking any script.
Ensure the Namespace CLI `nsc` is available in the agent environment before
running the scripts. In Nix environments, install the `namespace-cli` package.
If the CLI is not authenticated yet, run `nsc auth login` first.
Ensure `gnutar` and `gzip` are available locally before running the test helper.

Skill-local script paths such as `scripts/run-remote-test.sh` are resolved
relative to this skill directory, not relative to the repository root.

Successful runs should prioritize the remote execution output itself.
Infra/bootstrap output belongs in saved logs unless debug mode is enabled or a
phase fails.

## Workflow

1. Read `references/env.md` and verify the required variables and CLI
   prerequisites are satisfied.
2. Read `references/usage.md` to confirm the correct test attribute name.
   Treat its flake attribute and app names as generic examples unless the
   current repository defines matching outputs.
3. If the Nix cache volume may be cold (first use or after a long gap),
   run `scripts/ensure-nix-cache.sh` first.
4. Choose the helper that matches the task:
   - `scripts/run-remote-command.sh '<shell-command>'` for arbitrary execution
   - `scripts/run-remote-test.sh <test-attr>` for flake check builds
5. Report the execution output, exit code, and saved log paths to the user.
6. Never leave instances running after the script exits.
   The scripts create an ephemeral instance, connect through `nsc ssh`, and
   destroy it automatically via EXIT trap.
7. On bare Namespace instances, expect Nix to run in single-user mode unless
   the remote image explicitly provides the `nixbld` group. The helper scripts
   handle that by passing `--option build-users-group ""` to remote Nix calls.

## Rules

- Always use ephemeral instances. Never use Devboxes for test execution.
- Never modify `NSC_DURATION` beyond 60m without explicit user instruction.
- The warm-cache step is optional and idempotent; when in doubt, run it.
- Treat a non-zero exit from the test script as a test failure, not a tool error.
- `run-remote-command.sh` expects a single shell snippet argument. Quote it.
- Default output policy:
  - full remote execution output is streamed live and saved to `execution.txt`
  - infra/setup logs are saved to `infra.log`
  - only surface infra detail inline when debug is enabled or a phase fails
  - if execution goes quiet, emit periodic keepalive lines so agents can tell the run is still alive
