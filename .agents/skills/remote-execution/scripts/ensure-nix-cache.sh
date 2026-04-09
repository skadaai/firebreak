#!/usr/bin/env bash
# Warms the Nix cache volume so that run-remote-test.sh skips the Nix install step
# on all subsequent runs. Run once after workspace setup, or whenever nixpkgs is updated.
set -euo pipefail

NSC_MACHINE=${NSC_MACHINE:-"4x8"}
NSC_DURATION=${NSC_DURATION:-"15m"}
NSC_NIX_CACHE_TAG=${NSC_NIX_CACHE_TAG:-"nix-store"}

if ! command -v nsc >/dev/null 2>&1; then
  echo "nsc is required but not on PATH" >&2
  echo "install the Namespace CLI in the agent environment (Nix package: namespace-cli)" >&2
  exit 127
fi

if ! nsc auth check-login >/dev/null 2>&1; then
  echo "nsc is installed but not authenticated. Run 'nsc auth login' first." >&2
  exit 1
fi

INSTANCE_ID_FILE=$(mktemp)
cleanup() {
  local id
  id=$(cat "$INSTANCE_ID_FILE" 2>/dev/null || true)
  [[ -n "$id" ]] && { nsc destroy --force "$id" >/dev/null 2>&1 || true; }
  rm -f "$INSTANCE_ID_FILE"
}
trap cleanup EXIT INT TERM

remote_bash() {
  local script=$1
  printf '%s\n' "$script" | nsc ssh --disable-pty "$INSTANCE_ID" -- bash -s --
}

wait_for_shell() {
  local attempt output
  for attempt in $(seq 1 40); do
    if output=$(nsc ssh --disable-pty "$INSTANCE_ID" -- true 2>&1); then
      return 0
    fi
    if printf '%s\n' "$output" | grep -qiE 'FailedPrecondition|failed to start'; then
      printf '%s\n' "$output" >&2
      return 1
    fi
    sleep 3
  done
  echo "Timed out waiting for instance $INSTANCE_ID to accept nsc ssh." >&2
  return 124
}

echo "→ Creating warm-up instance..."
nsc create \
  --bare \
  --machine_type "$NSC_MACHINE" \
  --duration "$NSC_DURATION" \
  --volume "cache:$NSC_NIX_CACHE_TAG:/nix:50gb" \
  --purpose "Warm Nix cache for remote execution" \
  --cidfile "$INSTANCE_ID_FILE"

INSTANCE_ID=$(cat "$INSTANCE_ID_FILE")

echo "→ Instance: $INSTANCE_ID"
echo "→ Waiting for remote shell..."
wait_for_shell

echo "→ Installing Nix into cache volume '$NSC_NIX_CACHE_TAG'..."
remote_bash "
set -euo pipefail
NIX_BIN=/nix/var/nix/profiles/default/bin/nix
if [[ ! -x \$NIX_BIN ]]; then
  curl -fsSL https://install.determinate.systems/nix \
    | sh -s -- install linux --determinate --init none --no-confirm
fi
echo \"→ Pre-fetching nixpkgs...\"
\$NIX_BIN --option build-users-group \"\" \
  --accept-flake-config --extra-experimental-features \"nix-command flakes\" \
  flake metadata \"github:nixos/nixpkgs/nixos-unstable\" --json > /dev/null
echo \"→ Done. Cache is ready.\"
"

echo "→ Cache volume '$NSC_NIX_CACHE_TAG' is seeded. Future test runs will skip the Nix install step."
