set -eu

repo_root=@REPO_ROOT@
if ! [ -f "$repo_root/bin/firebreak.js" ] || ! [ -f "$repo_root/package.json" ]; then
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
node_bin=$(command -v node)

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
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
    "$node_bin" "$repo_root/bin/firebreak.js" run codex 2>&1
)
missing_nix_status=$?
set -e

if [ "$missing_nix_status" -eq 0 ] || ! printf '%s\n' "$missing_nix_output" | grep -F -q "Nix is not installed"; then
  printf '%s\n' "$missing_nix_output" >&2
  echo "launcher smoke did not fail clearly when Nix was missing" >&2
  exit 1
fi

rm -f "$nix_args_path" "$nix_cwd_path"

vms_output=$(
  cd "$repo_root"
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
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
    FIREBREAK_LAUNCHER_KVM_PATH="$fake_kvm_path" \
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
set +e
missing_kvm_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_LAUNCHER_KVM_PATH="$smoke_tmp_dir/missing-kvm" \
    node "$repo_root/bin/firebreak.js" internal validate run test-smoke-codex 2>&1
)
missing_kvm_status=$?
set -e

if [ "$missing_kvm_status" -eq 0 ] || ! printf '%s\n' "$missing_kvm_output" | grep -F -q "needs KVM access"; then
  printf '%s\n' "$missing_kvm_output" >&2
  echo "launcher smoke did not block non-diagnostic commands when KVM was unavailable" >&2
  exit 1
fi

if [ -f "$nix_args_path" ]; then
  cat "$nix_args_path" >&2
  echo "launcher smoke should not invoke nix when KVM preflight fails" >&2
  exit 1
fi

printf '%s\n' "Firebreak npx launcher smoke test passed"
