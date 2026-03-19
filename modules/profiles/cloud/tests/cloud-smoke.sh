set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

workspace_dir=$(mktemp -d)
output_dir=$(mktemp -d)
state_dir=$(mktemp -d)
timeout_output_dir=$(mktemp -d)

trap 'rm -rf "$workspace_dir" "$output_dir" "$state_dir" "$timeout_output_dir"' EXIT INT TERM

cat >"$workspace_dir/timeout-fixture.sh" <<'EOF'
#!/bin/sh
sleep 5
EOF
chmod 0755 "$workspace_dir/timeout-fixture.sh"

job_cmd() {
  FIREBREAK_STATE_DIR="$state_dir" \
    @JOB_PACKAGE_BIN@ "$@"
}

job_cmd \
  --job-id smoke-success \
  --workspace-dir "$workspace_dir" \
  --output-dir "$output_dir" \
  --prompt "Inspect the repository and print a short architecture summary to standard output" \
  --timeout-seconds 180 \
  --max-jobs 1

if ! [ -f "$output_dir/stdout" ] || ! grep -q "Inspect the repository and print a short architecture summary to standard output" "$output_dir/stdout"; then
  echo "cloud smoke success case did not capture expected stdout" >&2
  exit 1
fi

if ! [ -f "$output_dir/exit_code" ] || [ "$(cat "$output_dir/exit_code")" != "0" ]; then
  echo "cloud smoke success case did not report exit code 0" >&2
  exit 1
fi

set +e
job_cmd \
  --job-id smoke-missing-input \
  --workspace-dir "$workspace_dir/missing" \
  --output-dir "$output_dir" \
  --prompt "Inspect the repository and print a short architecture summary to standard output" \
  --timeout-seconds 180 \
  --max-jobs 1 >/dev/null 2>&1
missing_input_status=$?
set -e

if [ "$missing_input_status" -eq 0 ]; then
  echo "cloud smoke missing-input case did not fail" >&2
  exit 1
fi

if ! [ -f "$output_dir/exit_code" ] || [ "$(cat "$output_dir/exit_code")" != "2" ]; then
  echo "cloud smoke missing-input case did not persist exit code 2" >&2
  exit 1
fi

mkdir -p "$state_dir/running/fake-capacity"

set +e
job_cmd \
  --job-id smoke-capacity-2 \
  --workspace-dir "$workspace_dir" \
  --output-dir "$output_dir" \
  --prompt "Inspect the repository and print a short architecture summary to standard output" \
  --timeout-seconds 180 \
  --max-jobs 1 >/dev/null 2>&1
capacity_status=$?
set -e

rm -rf "$state_dir/running/fake-capacity"

if [ "$capacity_status" -ne 125 ]; then
  echo "cloud smoke capacity case did not reject with exit code 125" >&2
  exit 1
fi

set +e
job_cmd \
  --job-id smoke-timeout \
  --workspace-dir "$workspace_dir" \
  --output-dir "$timeout_output_dir" \
  --prompt "Run the timeout validation fixture" \
  --timeout-seconds 1 \
  --max-jobs 1 >/dev/null 2>&1
timeout_status=$?
set -e

if [ "$timeout_status" -ne 124 ]; then
  echo "cloud smoke timeout case did not return exit code 124" >&2
  exit 1
fi

if ! [ -f "$timeout_output_dir/exit_code" ] || [ "$(cat "$timeout_output_dir/exit_code")" != "124" ]; then
  echo "cloud smoke timeout case did not persist exit code 124" >&2
  exit 1
fi

printf '%s\n' "Firebreak cloud job smoke test passed"
