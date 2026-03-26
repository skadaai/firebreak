# 015 Validation Guide

This guide defines the validation steps required to move spec 015 out of its initial implementation phase.

Markdown is the right format here because the validation contract needs to stay human-readable, reviewable in Git, and easy to update as the implementation slices evolve.

## Automated Tests

Run these from the repository root.

### 1. Parse the new guest and recipe scripts

Purpose: catch shell-level regressions in the shared worker runtime, packaged-node bootstrap readiness helper, and recipe-owned smoke scripts before booting VMs.

```sh
bash -n modules/node-cli/guest/bootstrap.sh
bash -n modules/profiles/local/guest/firebreak-worker-cli.sh
bash -n modules/base/tests/test-smoke-worker-guest-bridge.sh
bash -n external/agent-orchestrator/tests/test-smoke-worker-proxy.sh
bash -n external/agent-orchestrator/tests/test-smoke-worker-spawn.sh
```

Expected result:

- all commands exit `0`

### 2. Validate the host-broker worker engine

Purpose: prove the host-side `firebreak worker` broker still creates, lists, inspects, stops, and cleans up workers after the worker-kind and readiness changes.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-worker"
```

Expected result:

- the smoke exits `0`
- the output includes `Firebreak worker smoke test passed`

### 3. Validate the public Firebreak CLI route

Purpose: prove the public `firebreak` CLI still exposes the worker noun correctly after the orchestration-layer changes.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-firebreak-cli-surface"
```

Expected result:

- the smoke exits `0`
- the output includes the worker route coverage from the CLI surface smoke

### 4. Validate the guest bridge and per-kind concurrency limit

Purpose: prove a bridge-enabled guest can call `firebreak worker`, observe machine-readable metadata, clean up workers, and hit a declared `max_instances` limit.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD#firebreak-test-smoke-worker-guest-bridge"
```

Expected result:

- the smoke exits `0`
- the output includes `Firebreak worker guest bridge smoke test passed`

### 5. Evaluate the external recipe outputs

Purpose: prove the external orchestrator recipe exports the expected packages and checks, including recipe-owned worker smoke outputs.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake show "path:$PWD/external/agent-orchestrator" --override-input firebreak "path:$PWD"
```

Expected result:

- evaluation exits `0`
- the output includes:
  - `firebreak-test-smoke-agent-orchestrator-worker-proxy`
  - `firebreak-test-smoke-agent-orchestrator-worker-spawn`

### 6. Validate the external recipe bootstrap and worker-proxy wrapper

Purpose: prove the external recipe can wait for bootstrap, resolve the packaged `ao` CLI, and expose the `codex` worker-proxy wrapper without modifying Firebreak core.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD/external/agent-orchestrator#firebreak-test-smoke-agent-orchestrator-worker-proxy" --override-input firebreak "path:$PWD"
```

Expected result:

- the smoke exits `0`
- the output includes `Agent Orchestrator worker proxy smoke test passed`

### 7. Validate real declared-worker creation from the external recipe

Purpose: prove the first external orchestrator recipe can spawn a declared `firebreak` worker kind through the guest-visible `firebreak worker` surface.

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$PWD/external/agent-orchestrator#firebreak-test-smoke-agent-orchestrator-worker-spawn" --override-input firebreak "path:$PWD"
```

Expected result:

- the smoke exits `0`
- the output includes `Agent Orchestrator worker run smoke test passed`

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

### 2. Spawn a declared worker manually from inside the orchestrator VM

Purpose: verify the guest-visible workflow directly.

Run inside the guest:

```sh
firebreak-bootstrap-wait
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
