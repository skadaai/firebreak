#!/usr/bin/env bash
# Warms the Nix cache volume so that run-remote-test.sh skips the Nix install step
# on all subsequent runs. Run once after workspace setup, or whenever nixpkgs is updated.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./remote-execution-lib.sh
source "$SCRIPT_DIR/remote-execution-lib.sh"

NSC_DURATION=${NSC_DURATION:-"15m"}

remote_execution_init
remote_execution_announce_run_dir
trap remote_execution_cleanup EXIT INT TERM

remote_execution_require_prereqs
remote_execution_create_instance
remote_execution_wait_until_ready

REMOTE_EXECUTION_PHASE="nix-cache-warm"
echo "→ Installing Nix into cache volume '$NSC_NIX_CACHE_TAG'..."
if remote_execution_run_remote_infra "nix-cache-warm" "
set -euo pipefail
NIX_BIN=/nix/var/nix/profiles/default/bin/nix
if [[ ! -x \$NIX_BIN ]]; then
  curl -fsSL https://install.determinate.systems/nix \
    | sh -s -- install linux --determinate --init none --no-confirm
fi
echo \"Pre-fetching nixpkgs...\"
\$NIX_BIN --option build-users-group \"\" \
  --accept-flake-config --extra-experimental-features \"nix-command flakes\" \
  flake metadata \"github:nixos/nixpkgs/nixos-unstable\" --json > /dev/null
echo \"Cache is ready.\"
"; then
  :
else
  status=$?
  remote_execution_fail "nix-cache-warm" "$status"
fi

remote_execution_write_summary "ok" "nix-cache-warm" 0
echo "→ Cache volume '$NSC_NIX_CACHE_TAG' is seeded. Future runs will skip the Nix install step."
echo "Summary: $SUMMARY_FILE"
echo "Infra log: $INFRA_LOG"
