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
| `NSC_MACHINE`       | `4x8`        | Instance shape: `<vcpu>x<ram_gb>`. Use `8x16` for heavy or parallel tests. |
| `NSC_DURATION`      | `30m`        | Hard TTL. Instance is auto-destroyed after this regardless of outcome.      |
| `NSC_NIX_CACHE_TAG` | `nix-store`  | Tag for the cache volume backing `/nix`. Change per project to isolate stores. |

## Recommended `.envrc` block

```bash
export NSC_MACHINE="4x8"
export NSC_DURATION="30m"
export NSC_NIX_CACHE_TAG="nix-store"
```

## Notes

- `NSC_DURATION` is a safety net, not the expected runtime. The instance is
  destroyed immediately by the EXIT trap when the test finishes. Set it
  generously to cover slow first-run cache population.
- `NSC_NIX_CACHE_TAG` scopes the `/nix` cache volume. Two projects sharing the
  same tag share the same Nix store, saving disk and speeding up installs.
  Use distinct tags only if you need hermetic store isolation between projects.
- The helper scripts use `nsc ssh` for command execution and file transfer, so
  they do not require a separate SSH endpoint or manual key injection.
- Bare Namespace instances may not expose a `nixbld` group even after Nix is
  installed. The helper scripts force single-user Nix for remote commands by
  passing `--option build-users-group ""`.
