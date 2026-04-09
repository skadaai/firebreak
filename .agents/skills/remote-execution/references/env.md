# Environment Variables

## Prerequisites

- The Namespace CLI `nsc` must be available in the agent environment.
  In Nix environments, install the `namespace-cli` package.
- The CLI must already be authenticated for the target workspace.
  Run `nsc auth login` if needed.
- `gnutar` and `gzip` must be available locally because the test helper packs
  and streams the workspace archive from the local environment.

## Optional

| Variable            | Default      | Description                                                                 |
|---------------------|--------------|-----------------------------------------------------------------------------|
| `NSC_MACHINE`       | `4x8`        | Instance shape: `<vcpu>x<ram_gb>`. Start here by default and only increase after evidence that more resources are required. |
| `NSC_DURATION`      | `30m`        | Hard TTL. Instance is auto-destroyed after this regardless of outcome.      |
| `NSC_NIX_CACHE_TAG` | `nix-store`  | Tag for the cache volume backing `/nix`. Change per project to isolate stores. |
| `NSC_NIX_CACHE_SCOPE` | auto       | Optional warm-marker scope. Defaults to a repo-specific key derived from `flake.lock` or `flake.nix`. |
| `NSC_NIX_CACHE_FORCE` | `0`        | When set to `1`, ignore the existing warm marker and force the expensive warm step again. |
| `NSC_DEBUG`         | `0`          | When set to `1`, stream infra/bootstrap logs live instead of keeping them mostly in `infra.log`. |
| `NSC_TRACE`         | `0`          | When set to `1`, prepend `set -x` to the remote execution script for shell-level tracing. |
| `NSC_LOG_DIR`       | unset        | If set, write `infra.log`, `execution.txt`, and `summary.txt` into this directory instead of a temp dir. |
| `NSC_HEARTBEAT_SECONDS` | `30`     | Print a keepalive line when the main remote execution stays silent for this many seconds. |

## Recommended `.envrc` block

```bash
export NSC_MACHINE="4x8"
export NSC_DURATION="30m"
export NSC_NIX_CACHE_TAG="nix-store"
export NSC_NIX_CACHE_SCOPE=""
export NSC_NIX_CACHE_FORCE="0"
export NSC_DEBUG="0"
export NSC_TRACE="0"
export NSC_HEARTBEAT_SECONDS="30"
```

## Notes

- `NSC_DURATION` is a safety net, not the expected runtime. The instance is
  destroyed immediately by the EXIT trap when the test finishes. Set it
  generously to cover slow first-run cache population.
- Be conservative with machine size. Start with `4x8` unless the user explicitly
  asks for more or prior failures show the workload is resource-bound.
- `NSC_NIX_CACHE_TAG` scopes the `/nix` cache volume. Two projects sharing the
  same tag share the same Nix store, saving disk and speeding up installs.
  Use distinct tags only if you need hermetic store isolation between projects.
- The helper scripts use `nsc ssh` for command execution and file transfer, so
  they do not require a separate SSH endpoint or manual key injection.
- This skill requires a modern `nsc` build that supports `nsc instance upload`.
  Older CLI builds are rejected during preflight instead of using a legacy fallback.
- Recommended preflight:
  `nsc auth check-login && nsc instance upload --help`
- Bare Namespace instances may not expose a `nixbld` group even after Nix is
  installed. The helper scripts force single-user Nix for remote commands by
  passing `--option build-users-group ""`.
- Successful runs should mostly show the remote execution output itself.
  Bootstrap and transport details are captured in `infra.log` and printed
  inline only on failure or when `NSC_DEBUG=1`.
- `execution.txt` contains only remote stdout/stderr. A successful silent run
  can legitimately leave it empty; use `summary.txt` to confirm that execution
  started, finished, and exited successfully.
- Long quiet executions emit a keepalive line on the terminal after
  `NSC_HEARTBEAT_SECONDS` of silence so agents do not assume the run stalled.
- The run directory is printed at startup. `summary.txt` is live-updated while
  the run is in progress, so it can be inspected mid-run.
- Default logging is parallel-safe because each run uses a fresh temp directory.
  If you set `NSC_LOG_DIR`, use a unique path per concurrent run.
- `ensure-nix-cache.sh` only avoids the expensive warm step when the same
  `NSC_NIX_CACHE_TAG` resolves to the same underlying Namespace cache volume.
  Within a reused volume, the warm marker is keyed by `NSC_NIX_CACHE_SCOPE`.
