set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
workspace_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-cloud-job-workspace.XXXXXX")
output_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-cloud-job-output.XXXXXX")
state_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-cloud-job-state.XXXXXX")
timeout_output_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-cloud-job-timeout-output.XXXXXX")
trap 'rm -rf "$workspace_dir" "$output_dir" "$state_dir" "$timeout_output_dir"' EXIT INT TERM

printf '%s\n' 'echo "Run the timeout validation fixture" > /dev/null' >"$workspace_dir/timeout-fixture.sh"
chmod +x "$workspace_dir/timeout-fixture.sh"

@JOB_PACKAGE_BIN@ \
  --job-id smoke-success \
  --workspace-dir "$workspace_dir" \
  --output-dir "$output_dir" \
  --state-dir "$state_dir" \
  --prompt "Inspect the repository and print a short architecture summary to standard output"

if ! [ -f "$output_dir/stdout" ]; then
  echo "cloud job smoke did not produce stdout output" >&2
  exit 1
fi

if ! grep -q 'Inspect the repository and print a short architecture summary to standard output' "$output_dir/stdout"; then
  cat "$output_dir/stdout" >&2
  echo "cloud job smoke did not preserve the expected prompt output" >&2
  exit 1
fi

set +e
@JOB_PACKAGE_BIN@ \
  --job-id smoke-timeout \
  --workspace-dir "$workspace_dir" \
  --output-dir "$timeout_output_dir" \
  --state-dir "$state_dir" \
  --prompt "Run the timeout validation fixture" \
  --timeout-seconds 1
timeout_status=$?
set -e

if [ "$timeout_status" -ne 124 ]; then
  echo "cloud job smoke timeout scenario did not exit with 124" >&2
  exit 1
fi

if ! [ -f "$timeout_output_dir/exit_code" ] || ! grep -q '^124$' "$timeout_output_dir/exit_code"; then
  echo "cloud job smoke timeout scenario did not preserve exit code" >&2
  exit 1
fi

printf '%s\n' "Firebreak cloud job smoke test passed"
