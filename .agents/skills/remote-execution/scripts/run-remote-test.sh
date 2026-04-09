#!/usr/bin/env bash
set -euo pipefail

TEST_ATTR=${1:-}

if [[ -z "$TEST_ATTR" ]]; then
  echo "usage: $0 <test-attr>" >&2
  echo "pass an explicit flake check attribute, e.g. checks.x86_64-linux.some-vm-test" >&2
  exit 64
fi

NSC_MACHINE=${NSC_MACHINE:-"4x8"}
NSC_DURATION=${NSC_DURATION:-"30m"}
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

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required locally. Provide GNU tar (package name: gnutar) and retry." >&2
  exit 127
fi

if ! command -v gzip >/dev/null 2>&1; then
  echo "gzip is required locally. Provide gzip and retry." >&2
  exit 127
fi

INSTANCE_ID_FILE=$(mktemp)
ARCHIVE_FILE=$(mktemp)

cleanup() {
  local id
  id=$(cat "$INSTANCE_ID_FILE" 2>/dev/null || true)
  if [[ -n "$id" ]]; then
    echo "→ Destroying instance $id..."
    nsc destroy --force "$id" >/dev/null 2>&1 || true
  fi
  rm -f "$INSTANCE_ID_FILE"
  rm -f "$ARCHIVE_FILE"
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

echo "→ Creating ephemeral instance (shape: $NSC_MACHINE, duration: $NSC_DURATION)..."
nsc create \
  --bare \
  --machine_type "$NSC_MACHINE" \
  --duration "$NSC_DURATION" \
  --volume "cache:$NSC_NIX_CACHE_TAG:/nix:50gb" \
  --purpose "Remote test execution" \
  --label "test=$TEST_ATTR" \
  --cidfile "$INSTANCE_ID_FILE"

INSTANCE_ID=$(cat "$INSTANCE_ID_FILE")

echo "→ Instance: $INSTANCE_ID"
echo "→ Waiting for remote shell..."
wait_for_shell

echo "→ Ensuring Nix is installed..."
remote_bash "
set -euo pipefail
NIX_BIN=/nix/var/nix/profiles/default/bin/nix
if [[ -x \$NIX_BIN ]]; then
  echo \"  Nix found in cache, skipping install.\"
else
  echo \"  Installing Nix (first run - will be cached for future runs)...\"
  curl -fsSL https://install.determinate.systems/nix \
    | sh -s -- install linux --determinate --init none --no-confirm
fi
"

echo "→ Creating workspace archive..."
tar -czf "$ARCHIVE_FILE" \
  --exclude='.git' \
  --exclude='result' \
  --exclude='.direnv' \
  --exclude='.agent-sandbox-codex-ssh' \
  .

echo "→ Uploading and unpacking workspace..."
remote_bash "
set -euo pipefail
rm -rf /workspace
mkdir -p /workspace
"
nsc ssh --disable-pty "$INSTANCE_ID" -- tar -xzf - -C /workspace < "$ARCHIVE_FILE"

echo "→ Running: $TEST_ATTR"
remote_bash "
set -euo pipefail
NIX_BIN=/nix/var/nix/profiles/default/bin/nix
if [[ ! -x \$NIX_BIN ]]; then
  echo \"nix is missing after install step\" >&2
  exit 1
fi
cd /workspace
\$NIX_BIN --option build-users-group \"\" \
  --accept-flake-config --extra-experimental-features \"nix-command flakes\" \
  build -L \".#${TEST_ATTR}\"
"
