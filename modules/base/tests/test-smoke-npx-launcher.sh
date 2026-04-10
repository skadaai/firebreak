set -eu

repo_root=@REPO_ROOT@
if ! [ -f "$repo_root/bin/firebreak.js" ] || ! [ -f "$repo_root/bin/dev-flow.js" ] || ! [ -f "$repo_root/package.json" ]; then
  echo "launcher smoke could not resolve the Firebreak source root" >&2
  exit 1
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-npx-launcher.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

fake_bin_dir=$smoke_tmp_dir/bin
empty_bin_dir=$smoke_tmp_dir/empty
fake_kvm_path=$smoke_tmp_dir/kvm
nix_args_path=$smoke_tmp_dir/nix.args
nix_cwd_path=$smoke_tmp_dir/nix.cwd
mkdir -p "$fake_bin_dir" "$empty_bin_dir"
: >"$fake_kvm_path"
node_bin=$(command -v node || true)

if [ -z "$node_bin" ]; then
  echo "launcher smoke requires \`node\` on PATH" >&2
  exit 1
fi

assert_no_nix_invocation() {
  context=$1

  if [ -f "$nix_args_path" ]; then
    cat "$nix_args_path" >&2
    echo "launcher smoke should not invoke nix for $context" >&2
    exit 1
  fi

  if [ -f "$nix_cwd_path" ]; then
    cat "$nix_cwd_path" >&2
    echo "launcher smoke should not invoke nix for $context" >&2
    exit 1
  fi
}

cat >"$fake_bin_dir/nix" <<EOF
#!/usr/bin/env bash
set -eu
if [ "\${1:-}" = "--version" ]; then
  printf '%s\n' 'nix smoke shim'
  exit 0
fi
printf '%s\n' "\$PWD" >"$nix_cwd_path"
printf '%s\n' "\$@" >"$nix_args_path"
exit 0
EOF
chmod +x "$fake_bin_dir/nix"

set +e
missing_nix_output=$(
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$empty_bin_dir" \
    "$node_bin" "$repo_root/bin/firebreak.js" run codex 2>&1
)
missing_nix_status=$?
set -e

if [ "$missing_nix_status" -eq 0 ] || ! printf '%s\n' "$missing_nix_output" | grep -F -q "Nix is not installed"; then
  printf '%s\n' "$missing_nix_output" >&2
  echo "launcher smoke did not fail clearly when Nix was missing" >&2
  exit 1
fi

set +e
unsupported_arch_output=$(
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$empty_bin_dir" \
    FIREBREAK_LAUNCHER_TEST_PLATFORM=linux \
    FIREBREAK_LAUNCHER_TEST_ARCH=ia32 \
    "$node_bin" "$repo_root/bin/firebreak.js" help 2>&1
)
unsupported_arch_status=$?
set -e

if [ "$unsupported_arch_status" -eq 0 ] || ! printf '%s\n' "$unsupported_arch_output" | grep -F -q "aarch64-darwin hosts"; then
  printf '%s\n' "$unsupported_arch_output" >&2
  echo "launcher smoke did not reject unsupported Linux architectures clearly" >&2
  exit 1
fi

rm -f "$nix_args_path" "$nix_cwd_path"

vms_output=$(
  cd "$repo_root"
  PATH="$fake_bin_dir:$PATH" \
    node "$repo_root/bin/firebreak.js" vms
)

if ! printf '%s\n' "$vms_output" | grep -F -q "codex"; then
  printf '%s\n' "$vms_output" >&2
  echo "launcher smoke did not print the VM catalog through the local shell path" >&2
  exit 1
fi

if [ -f "$nix_args_path" ] || [ -f "$nix_cwd_path" ]; then
  echo "launcher smoke should not invoke nix for the local VM catalog path" >&2
  exit 1
fi

rm -f "$nix_args_path" "$nix_cwd_path"

doctor_output=$(
  cd "$smoke_tmp_dir"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_TEST_PLATFORM=linux \
    FIREBREAK_LAUNCHER_TEST_ARCH=arm64 \
    node "$repo_root/bin/firebreak.js" doctor --json
)

if ! printf '%s\n' "$doctor_output" | grep -F -q '"project_root":'; then
  printf '%s\n' "$doctor_output" >&2
  echo "launcher smoke did not run doctor through the packaged shell path" >&2
  exit 1
fi

if [ -f "$nix_args_path" ] || [ -f "$nix_cwd_path" ]; then
  echo "launcher smoke should not invoke nix for doctor --json" >&2
  exit 1
fi

rm -f "$nix_args_path" "$nix_cwd_path"

darwin_vms_output=$(
  cd "$repo_root"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_TEST_PLATFORM=darwin \
    FIREBREAK_LAUNCHER_TEST_ARCH=arm64 \
    node "$repo_root/bin/firebreak.js" vms
)

if ! printf '%s\n' "$darwin_vms_output" | grep -F -q "codex"; then
  printf '%s\n' "$darwin_vms_output" >&2
  echo "launcher smoke did not accept Apple Silicon macOS for local-only commands" >&2
  exit 1
fi

assert_no_nix_invocation "the Apple Silicon macOS VM catalog path"

set +e
intel_mac_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_TEST_PLATFORM=darwin \
    FIREBREAK_LAUNCHER_TEST_ARCH=x64 \
    node "$repo_root/bin/firebreak.js" doctor 2>&1
)
intel_mac_status=$?
set -e

if [ "$intel_mac_status" -eq 0 ] || ! printf '%s\n' "$intel_mac_output" | grep -F -q "Apple Silicon"; then
  printf '%s\n' "$intel_mac_output" >&2
  echo "launcher smoke did not reject Intel Macs clearly" >&2
  exit 1
fi

assert_no_nix_invocation "the Intel Mac rejection path"

rm -f "$nix_args_path" "$nix_cwd_path"

darwin_validate_output=$(
  cd "$repo_root"
  PATH="$fake_bin_dir:$PATH" \
    DEV_FLOW_LAUNCHER_TEST_PLATFORM=darwin \
    DEV_FLOW_LAUNCHER_TEST_ARCH=arm64 \
    DEV_FLOW_LAUNCHER_KVM_PATH="$smoke_tmp_dir/missing-kvm" \
    node "$repo_root/bin/dev-flow.js" validate run test-smoke-codex 2>&1
)

if ! [ -f "$nix_args_path" ]; then
  printf '%s\n' "$darwin_validate_output" >&2
  echo "launcher smoke should invoke nix for Apple Silicon macOS validation without KVM preflight" >&2
  exit 1
fi

rm -f "$nix_args_path" "$nix_cwd_path"

linux_validate_output=$(
  cd "$repo_root"
  PATH="$fake_bin_dir:$PATH" \
    DEV_FLOW_LAUNCHER_KVM_PATH="$smoke_tmp_dir/missing-kvm" \
    node "$repo_root/bin/dev-flow.js" validate run test-smoke-codex 2>&1
)

if ! [ -f "$nix_args_path" ]; then
  printf '%s\n' "$linux_validate_output" >&2
  echo "launcher smoke should invoke nix for Linux validation; expected $nix_args_path to exist" >&2
  exit 1
fi

rm -f "$nix_args_path" "$nix_cwd_path"

printf '%s\n' "Firebreak npx launcher smoke test passed"
