#!/usr/bin/env bash
# Unit tests for bin/firebreak.js launcher behavior.
# Tests spawn the Node.js script with fake stubs to verify edge cases.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
LAUNCHER="$REPO_ROOT/bin/firebreak.js"

if ! [ -f "$LAUNCHER" ]; then
  echo "test-unit-launcher: cannot find bin/firebreak.js at $LAUNCHER" >&2
  exit 1
fi

node_bin=$(command -v node 2>/dev/null || true)
if [ -z "$node_bin" ]; then
  echo "test-unit-launcher: node is not available, skipping" >&2
  exit 0
fi

pass_count=0
fail_count=0

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

fake_bin_dir="$tmp_dir/bin"
empty_bin_dir="$tmp_dir/empty"
fake_kvm_path="$tmp_dir/kvm"
nix_args_path="$tmp_dir/nix.args"
nix_cwd_path="$tmp_dir/nix.cwd"
mkdir -p "$fake_bin_dir" "$empty_bin_dir"
touch "$fake_kvm_path"
chmod 666 "$fake_kvm_path"

# Create a fake nix that records args and cwd
cat >"$fake_bin_dir/nix" <<EOF
#!/usr/bin/env bash
set -eu
if [ "\${1:-}" = "--version" ]; then
  printf '%s\n' 'nix (Nix) 2.18.0'
  exit 0
fi
printf '%s\n' "\$PWD" >"$nix_cwd_path"
printf '%s\n' "\$@" >"$nix_args_path"
exit 0
EOF
chmod +x "$fake_bin_dir/nix"

assert_eq() {
  description=$1
  actual=$2
  expected=$3
  if [ "$actual" = "$expected" ]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description" >&2
    echo "  expected: $(printf '%s' "$expected" | cat -A)" >&2
    echo "  actual:   $(printf '%s' "$actual" | cat -A)" >&2
  fi
}

assert_contains() {
  description=$1
  haystack=$2
  needle=$3
  if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description" >&2
    echo "  did not find: $needle" >&2
    echo "  in: $haystack" >&2
  fi
}

assert_not_contains() {
  description=$1
  haystack=$2
  needle=$3
  if ! printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description" >&2
    echo "  unexpectedly found: $needle" >&2
    echo "  in: $haystack" >&2
  fi
}

require_nix_arg() {
  description=$1
  expected=$2
  if ! grep -F -x -q -- "$expected" "$nix_args_path" 2>/dev/null; then
    fail_count=$((fail_count + 1))
    echo "FAIL: $description" >&2
    echo "  missing nix arg: $expected" >&2
    if [ -f "$nix_args_path" ]; then
      echo "  nix args were:" >&2
      cat "$nix_args_path" >&2
    else
      echo "  (nix args file not found)" >&2
    fi
  else
    pass_count=$((pass_count + 1))
  fi
}

# ---------------------------------------------------------------------------
# Nix missing: should fail with clear error message
# ---------------------------------------------------------------------------

set +e
missing_nix_output=$(
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$empty_bin_dir" \
    "$node_bin" "$LAUNCHER" doctor 2>&1
)
missing_nix_status=$?
set -e

if [ "$missing_nix_status" -eq 0 ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should exit nonzero when nix is missing" >&2
else
  pass_count=$((pass_count + 1))
fi

assert_contains "launcher reports nix not installed when nix is missing" \
  "$missing_nix_output" "Nix is not installed"

# ---------------------------------------------------------------------------
# Local checkout detection: runs from repo root, uses path: flake ref
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

(
  cd "$REPO_ROOT"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
    "$node_bin" "$LAUNCHER" vms >/dev/null 2>&1
)

require_nix_arg "local checkout uses path: flake ref" "path:$REPO_ROOT#firebreak"
require_nix_arg "local checkout passes --accept-flake-config" "--accept-flake-config"
require_nix_arg "local checkout passes --extra-experimental-features" "--extra-experimental-features"
require_nix_arg "local checkout passes nix-command flakes" "nix-command flakes"
require_nix_arg "local checkout passes run command" "run"
require_nix_arg "local checkout passes -- separator" "--"
require_nix_arg "local checkout passes vms arg" "vms"

# Verify cwd is preserved
if ! [ -f "$nix_cwd_path" ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: nix cwd was not recorded" >&2
else
  nix_actual_cwd=$(cat "$nix_cwd_path")
  assert_eq "launcher preserves cwd for local checkout case" "$nix_actual_cwd" "$REPO_ROOT"
fi

# ---------------------------------------------------------------------------
# GitHub fallback: runs from outside repo, uses github: flake ref
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"
outside_dir="$tmp_dir/outside"
mkdir -p "$outside_dir"

(
  cd "$outside_dir"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
    "$node_bin" "$LAUNCHER" doctor --json >/dev/null 2>&1
)

require_nix_arg "github fallback uses github: flake ref" "github:skadaai/firebreak#firebreak"
require_nix_arg "github fallback passes doctor arg" "doctor"
require_nix_arg "github fallback passes --json arg" "--json"

if ! [ -f "$nix_cwd_path" ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: github fallback cwd was not recorded" >&2
else
  nix_fallback_cwd=$(cat "$nix_cwd_path")
  assert_eq "launcher preserves cwd for github fallback case" "$nix_fallback_cwd" "$outside_dir"
fi

# ---------------------------------------------------------------------------
# FIREBREAK_LAUNCHER_PACKAGE_ROOT: uses forced local root
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

(
  cd "$outside_dir"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
    FIREBREAK_LAUNCHER_PACKAGE_ROOT="$REPO_ROOT" \
    "$node_bin" "$LAUNCHER" vms >/dev/null 2>&1
)

require_nix_arg "FIREBREAK_LAUNCHER_PACKAGE_ROOT forces local path: ref" "path:$REPO_ROOT#firebreak"

# ---------------------------------------------------------------------------
# FIREBREAK_LAUNCHER_PACKAGE_ROOT with invalid dir fails clearly
# ---------------------------------------------------------------------------

set +e
bad_root_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
    FIREBREAK_LAUNCHER_PACKAGE_ROOT="$tmp_dir/not-a-firebreak-checkout" \
    "$node_bin" "$LAUNCHER" vms 2>&1
)
bad_root_status=$?
set -e

if [ "$bad_root_status" -eq 0 ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should fail when FIREBREAK_LAUNCHER_PACKAGE_ROOT is invalid" >&2
else
  pass_count=$((pass_count + 1))
fi

assert_contains "launcher reports invalid FIREBREAK_LAUNCHER_PACKAGE_ROOT" \
  "$bad_root_output" "FIREBREAK_LAUNCHER_PACKAGE_ROOT"

# ---------------------------------------------------------------------------
# KVM missing blocks non-diagnostic commands (like internal validate)
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

set +e
missing_kvm_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$tmp_dir/nonexistent-kvm" \
    "$node_bin" "$LAUNCHER" internal validate run test-smoke-codex 2>&1
)
missing_kvm_status=$?
set -e

if [ "$missing_kvm_status" -eq 0 ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should fail when KVM is missing and command requires KVM" >&2
else
  pass_count=$((pass_count + 1))
fi

assert_contains "launcher reports KVM needed for internal commands" \
  "$missing_kvm_output" "needs KVM access"

# Nix should NOT have been invoked
if [ -f "$nix_args_path" ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should not invoke nix when KVM check fails for non-diagnostic command" >&2
else
  pass_count=$((pass_count + 1))
fi

# ---------------------------------------------------------------------------
# KVM missing warns but continues for diagnostic commands: doctor
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

kvm_warn_output=$(
  cd "$REPO_ROOT"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$tmp_dir/nonexistent-kvm" \
    "$node_bin" "$LAUNCHER" doctor 2>&1 || true
)

# Nix should have been invoked despite missing KVM
if ! [ -f "$nix_args_path" ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should invoke nix for doctor even when KVM is missing" >&2
else
  pass_count=$((pass_count + 1))
fi

assert_contains "launcher warns about KVM for doctor command" \
  "$kvm_warn_output" "Continuing because this command"

# ---------------------------------------------------------------------------
# KVM missing warns but continues for diagnostic commands: init
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

(
  cd "$REPO_ROOT"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$tmp_dir/nonexistent-kvm" \
    "$node_bin" "$LAUNCHER" init >/dev/null 2>&1 || true
)

if ! [ -f "$nix_args_path" ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should invoke nix for init even when KVM is missing" >&2
else
  pass_count=$((pass_count + 1))
fi

# ---------------------------------------------------------------------------
# KVM missing warns but continues for: vms
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

(
  cd "$REPO_ROOT"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$tmp_dir/nonexistent-kvm" \
    "$node_bin" "$LAUNCHER" vms >/dev/null 2>&1 || true
)

if ! [ -f "$nix_args_path" ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should invoke nix for vms even when KVM is missing" >&2
else
  pass_count=$((pass_count + 1))
fi

# ---------------------------------------------------------------------------
# KVM missing warns but continues for: help / --help / -h
# ---------------------------------------------------------------------------

for help_cmd in "help" "--help" "-h"; do
  rm -f "$nix_args_path" "$nix_cwd_path"

  (
    cd "$REPO_ROOT"
    PATH="$fake_bin_dir:$PATH" \
      FIREBREAK_LAUNCHER_KVM_PATH="$tmp_dir/nonexistent-kvm" \
      "$node_bin" "$LAUNCHER" "$help_cmd" >/dev/null 2>&1 || true
  )

  if ! [ -f "$nix_args_path" ]; then
    fail_count=$((fail_count + 1))
    echo "FAIL: launcher should invoke nix for '$help_cmd' even when KVM is missing" >&2
  else
    pass_count=$((pass_count + 1))
  fi
done

# ---------------------------------------------------------------------------
# KVM missing warns but continues when no command is given
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

(
  cd "$REPO_ROOT"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$tmp_dir/nonexistent-kvm" \
    "$node_bin" "$LAUNCHER" >/dev/null 2>&1 || true
)

if ! [ -f "$nix_args_path" ]; then
  fail_count=$((fail_count + 1))
  echo "FAIL: launcher should invoke nix even with no command when KVM is missing" >&2
else
  pass_count=$((pass_count + 1))
fi

# ---------------------------------------------------------------------------
# Argument forwarding: all args after firebreak.js are forwarded to nix run
# ---------------------------------------------------------------------------

rm -f "$nix_args_path" "$nix_cwd_path"

(
  cd "$REPO_ROOT"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
    "$node_bin" "$LAUNCHER" run codex --shell -- --version >/dev/null 2>&1
)

require_nix_arg "launcher forwards run command" "run"
require_nix_arg "launcher forwards vm name codex" "codex"
require_nix_arg "launcher forwards --shell flag" "--shell"
require_nix_arg "launcher forwards -- separator" "--"
require_nix_arg "launcher forwards --version after --" "--version"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

printf '%s\n' "Firebreak launcher unit tests passed"