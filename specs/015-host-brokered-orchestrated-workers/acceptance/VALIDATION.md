# 015 Validation Guide

This guide defines the validation steps required to move spec 015 out of its initial implementation phase.

Markdown is the right format here because the validation contract needs to stay human-readable, reviewable in Git, and easy to update as the implementation slices evolve.

## Recorded Outcome

The initial detached validation bar for spec 015 was satisfied on 2026-03-26.

Evidence used for that phase change:

- the fast automated checks in this repository passed for the host broker and the public CLI route
- the external recipe exports were validated through `flake show`
- the remaining runtime-critical behavior was confirmed manually inside the first external orchestrator VM:
  - `firebreak-bootstrap-wait` was available
  - `ao` and the `codex` worker-proxy wrapper were available
  - `firebreak worker run`, `ps`, `inspect`, `stop`, and `rm` behaved correctly
  - host-owned worker state and logs were present on the host
  - the fifth concurrent `codex` run was rejected at the configured `max_instances` limit

The spec was reopened later on 2026-03-26 after attached sibling-worker execution for the `firebreak` backend proved incomplete for interactive `codex` use. The next validation target is therefore narrower: prove attached `firebreak` worker execution in isolation before routing it back through the external orchestrator recipe.

## Automated Tests

Run these from the repository root.

### 1. Parse the new guest and recipe scripts

Purpose: catch shell-level regressions in the shared worker runtime, packaged-node bootstrap readiness helper, and recipe-owned smoke scripts before booting VMs.

```sh
bash -n modules/bun-agent/guest/bootstrap.sh
bash -n modules/node-cli/guest/shell-init.sh
bash -n modules/profiles/local/guest/prepare-agent-session.sh
bash -n modules/profiles/local/guest/dev-console-start.sh
bash -n modules/node-cli/guest/bootstrap.sh
bash -n modules/profiles/local/guest/firebreak-worker-cli.sh
bash -n modules/profiles/local/host/run-wrapper.sh
bash -n modules/base/tests/test-smoke-worker-guest-bridge.sh
bash -n modules/base/tests/test-smoke-worker-guest-bridge-interactive.sh
bash -n external/agent-orchestrator/tests/test-smoke-worker-proxy.sh
bash -n external/agent-orchestrator/tests/test-smoke-worker-spawn.sh
bash -n external/agent-orchestrator/tests/test-smoke-worker-interactive.sh
```

Expected result:

- all commands exit `0`

### 2. Validate direct packaged-cli readiness and guest lifecycle artifacts

Purpose: prove a direct packaged-cli VM run publishes reviewable machine-readable guest lifecycle state and preserves runtime evidence long enough for the smoke to assert it.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-codex-version"
```

Expected result:

- the smoke exits `0`
- the output includes a recognizable Codex version string
- the smoke verifies `bootstrap-state.json` reached `wrapper-ready`
- the smoke verifies `command-state.json` reached `command-exit`
- on failure, the smoke prints the preserved runtime directory instead of deleting it immediately

### 3. Validate the host-broker worker engine

Purpose: prove the host-side `firebreak worker` broker still creates, lists, inspects, stops, and cleans up workers after the worker-kind and readiness changes.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-worker"
```

Expected result:

- the smoke exits `0`
- the output includes `Firebreak worker smoke test passed`

### 4. Validate the public Firebreak CLI route

Purpose: prove the public `firebreak` CLI still exposes the worker noun correctly after the orchestration-layer changes.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-firebreak-cli-surface"
```

Expected result:

- the smoke exits `0`
- the output includes the worker route coverage from the CLI surface smoke

### 5. Validate the guest bridge and per-kind concurrency limit

Purpose: prove a bridge-enabled guest can call `firebreak worker`, observe machine-readable metadata, clean up workers, and hit a declared `max_instances` limit.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-worker-guest-bridge"
```

Expected result:

- the smoke exits `0`
- the output includes `Firebreak worker guest bridge smoke test passed`

### 6. Validate minimal attached `firebreak` worker execution

Purpose: prove the worker runtime can attach to a sibling Firebreak VM without the external orchestrator recipe in the way.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-worker-firebreak-attach"
```

Expected result:

- the smoke exits `0`
- the output includes `Firebreak attached firebreak worker smoke test passed`
- the attached run returns command output from the sibling worker instead of hanging after worker creation
- `firebreak worker debug --json` reports request-level bridge traces and nested runtime state for the attached worker
- `firebreak worker debug --json` reports the requested attached-terminal metadata, including `TERM`, `LINES`, and `COLUMNS`
- `firebreak worker debug --json` retains request-level attach trace evidence and any persisted bridge response exit code even after live request directories are removed
- attached traces distinguish the first sibling-runner byte from the first post-`command-start` command byte when both occur
- repeated attached packaged-worker runs against shared state prove either first-run install or seeded reuse, then later reuse through an explicit cache signal such as `toolchain-cache-hit`
- when the sibling worker is a packaged CLI, the debug output includes machine-readable guest bootstrap and command phases

### 7. Validate isolated interactive sibling-worker relay behavior

Purpose: prove the attached sibling-worker path can surface real command output and deliver live stdin through an isolated synthetic worker without depending on the external orchestrator recipe.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-worker-guest-bridge-interactive"
```

Expected result:

- the smoke exits `0`
- the output includes `__BRIDGE_INTERACTIVE_OK__`
- the attached session observes both `READY` and `ECHO:ping`
- on failure, the smoke preserves its isolated state directory and prints `firebreak worker debug --json`

### 8. Evaluate the external recipe outputs

Purpose: prove the external orchestrator recipe exports the expected packages and checks, including recipe-owned worker smoke outputs.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake show "path:$PWD/external/agent-orchestrator" --override-input firebreak "path:$PWD"
```

Expected result:

- evaluation exits `0`
- the output includes:
  - `firebreak-test-smoke-agent-orchestrator-worker-proxy`
  - `firebreak-test-smoke-agent-orchestrator-worker-spawn`
  - `firebreak-test-smoke-agent-orchestrator-worker-interactive`

### 9. Validate the external recipe bootstrap and worker-proxy wrapper

Purpose: prove the external recipe can wait for bootstrap, resolve the packaged `ao` CLI, and expose the `codex` worker-proxy wrapper without modifying Firebreak core.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD/external/agent-orchestrator#firebreak-test-smoke-agent-orchestrator-worker-proxy" --override-input firebreak "path:$PWD"
```

Expected result:

- the smoke exits `0`
- the output includes `Agent Orchestrator worker proxy smoke test passed`
- the smoke does not require the recipe test package to claim host forwarding ports that are unrelated to the worker-proxy behavior under test

### 10. Validate real declared-worker creation from the external recipe

Purpose: prove the first external orchestrator recipe can spawn a declared `firebreak` worker kind through the guest-visible `firebreak worker` surface.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD/external/agent-orchestrator#firebreak-test-smoke-agent-orchestrator-worker-spawn" --override-input firebreak "path:$PWD"
```

Expected result:

- the smoke exits `0`
- the output includes `Agent Orchestrator worker run smoke test passed`
- the smoke succeeds against the recipe's no-forward test package, so declared-worker validation remains independent of host port collisions

### 11. Validate plain interactive `codex` through the external recipe

Purpose: prove the external recipe can bring up a real attached sibling `codex` session, surface the nested worker banner, and do so through the no-forward test package rather than the port-forwarding integration package.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD/external/agent-orchestrator#firebreak-test-smoke-agent-orchestrator-worker-interactive" --override-input firebreak "path:$PWD"
```

Expected result:

- the smoke exits `0`
- the output includes `Agent Orchestrator interactive codex smoke test passed`
- the captured transcript includes nested terminal output from `firebreak-codex`, such as the nested worker welcome banner or an earlier boot marker identifying `firebreak-codex`

## Manual Tests

Run these after the automated steps pass or when the automated runs are too slow to provide enough confidence by themselves.

### 1. Launch the external orchestrator VM in shell mode

Purpose: confirm the recipe is usable interactively, not only through smoke wrappers.

```sh
FIREBREAK_VM_MODE=shell \
  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  run "path:$PWD/external/agent-orchestrator" \
  --override-input firebreak "path:$PWD"
```

Check:

- `firebreak-bootstrap-wait` is available
- `ao` is available
- `codex --version` reports the worker-proxy wrapper version string
- `firebreak worker debug --json` returns both a `local` section and a `bridge` section

### 2. Spawn a declared worker manually from inside the orchestrator VM

Purpose: verify the guest-visible workflow directly.

Run inside the guest:

```sh
firebreak-bootstrap-wait
firebreak worker debug --json
firebreak worker run --kind codex --workspace "$PWD" --json -- --version
firebreak worker ps
firebreak worker inspect <worker-id>
firebreak worker stop <worker-id>
firebreak worker rm <worker-id>
```

Check:

- the spawned worker gets a stable `worker_id`
- `inspect` reports backend `firebreak`
- `inspect` reports reviewable metadata and a sensible status transition
- `debug --json` reports the host bridge request and worker state without host-side `pgrep` or manual path inspection
- `debug --json` reports guest lifecycle state for packaged-cli bootstrap and command execution when those states exist
- `rm` removes the stopped worker cleanly

### 3. Verify host-owned runtime state for a `firebreak` worker

Purpose: confirm the worker runtime remains host-owned rather than guest-owned.

Check on the host after spawning a worker:

- the worker instance directory exists under:
  `/home/<user>/.local/state/firebreak/worker-broker/workers/<worker-id>/instance`
- the worker metadata exists under:
  `/home/<user>/.local/state/firebreak/worker-broker/workers/<worker-id>/metadata.json`
- the worker stdout and stderr logs exist under:
  `/home/<user>/.local/state/firebreak/worker-broker/workers/<worker-id>/stdout.log`
  `/home/<user>/.local/state/firebreak/worker-broker/workers/<worker-id>/stderr.log`
- the guest did not need direct nested-VM privileges to launch the worker

Where possible, prefer the guest-visible diagnosis command first:

```sh
firebreak worker debug --json
```

Use direct host path inspection only when the debug output itself looks incomplete or inconsistent.

### 4. Verify concurrency limits manually

Purpose: confirm the operator-facing failure mode is understandable when a kind reaches `max_instances`.

Run inside the guest:

```sh
firebreak worker run --kind codex --workspace "$PWD" -- --version &
firebreak worker run --kind codex --workspace "$PWD" -- --version &
firebreak worker run --kind codex --workspace "$PWD" -- --version &
firebreak worker run --kind codex --workspace "$PWD" -- --version &
firebreak worker run --kind codex --workspace "$PWD" -- --version
```

Check:

- once the configured limit is reached, Firebreak rejects the fifth spawn cleanly
- the rejection message names the kind and the configured limit

## Exit Criteria

Spec 015 is ready to move beyond `Initial implementation in progress` when:

1. every automated step above exits successfully in a real runtime environment
2. the manual checks confirm host-owned runtime behavior and understandable operator-facing semantics
3. the status file can truthfully say the first external orchestrator recipe is implemented and validated

That exit criterion was met for the detached lifecycle path, but the spec is reopened until the focused attached `firebreak` worker validation also passes.
