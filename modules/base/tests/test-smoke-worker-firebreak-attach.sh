#!/usr/bin/env bash
set -eu

default_firebreak_tmpdir=${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}
if [ -d /cache ] && [ -w /cache ]; then
  default_firebreak_tmpdir=/cache/firebreak
fi

choose_tmp_root() {
  if [ -n "${FIREBREAK_TEST_TMPDIR:-}" ]; then
    printf '%s\n' "$FIREBREAK_TEST_TMPDIR"
    return
  fi

  for candidate in \
    "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/firebreak-test/tmp" \
    "${FIREBREAK_TMPDIR:-$default_firebreak_tmpdir}/firebreak/tmp" \
    "/tmp/firebreak/tmp"
  do
    if mkdir -p "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf '%s\n' "/tmp"
}

firebreak_tmp_root=$(choose_tmp_root)
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-firebreak-attach.XXXXXX")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    echo "Firebreak attached firebreak worker smoke preserved artifacts under: $smoke_tmp_dir" >&2
  fi
  exit "$status"
}

trap cleanup EXIT INT TERM

state_dir=$smoke_tmp_dir/state
firebreak_state_dir=$smoke_tmp_dir/firebreak-state
workspace_dir=$smoke_tmp_dir/workspace
fake_bin_dir=$smoke_tmp_dir/bin
fake_nix_store_dir=$smoke_tmp_dir/fake-nix-store
mkdir -p "$state_dir" "$firebreak_state_dir" "$workspace_dir" "$fake_bin_dir" "$fake_nix_store_dir"
export FAKE_NIX_STORE_DIR="$fake_nix_store_dir"

cat >"$fake_bin_dir/nix" <<'EOF'
#!/usr/bin/env bash
set -eu

if [ "${1:-}" = "--version" ]; then
  printf '%s\n' 'nix smoke shim'
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    build)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

while [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; do
  shift
done

[ "$#" -gt 0 ] || exit 1
installable=$1
package_name=${installable##*#}
fake_out="$FAKE_NIX_STORE_DIR/$package_name"
mkdir -p "$fake_out/bin"
cat >"$fake_out/bin/$package_name" <<SCRIPT
#!/usr/bin/env bash
set -eu
printf '%s\n' 'codex-cli 0.114.0'
SCRIPT
chmod +x "$fake_out/bin/$package_name"
printf '%s\n' "$fake_out"
EOF
chmod +x "$fake_bin_dir/nix"

run_attach_version() {
  env \
    PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_STATE_MODE=outer-leak \
    FIREBREAK_CREDENTIAL_SLOT=outer-leak \
    FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH="$smoke_tmp_dir"/firebreak-worker-credential-slot-leak \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_STATE_DIR="$firebreak_state_dir" \
    FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
    FIREBREAK_FLAKE_REF="path:@REPO_ROOT@" \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --attach --backend firebreak --kind smoke-firebreak-attach --workspace "$workspace_dir" --package firebreak-codex -- --version
}

attach_output=$(run_attach_version)

if ! printf '%s\n' "$attach_output" | grep -F -q 'codex-cli'; then
  printf '%s\n' "$attach_output" >&2
  echo "attached firebreak worker smoke did not expose codex version output" >&2
  exit 1
fi

second_attach_output=$(run_attach_version)

if ! printf '%s\n' "$second_attach_output" | grep -F -q 'codex-cli'; then
  printf '%s\n' "$second_attach_output" >&2
  echo "second attached firebreak worker smoke run did not expose codex version output" >&2
  exit 1
fi

worker_count=$(find "$state_dir/workers" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$worker_count" != "2" ]; then
  find "$state_dir/workers" -mindepth 1 -maxdepth 1 -type d -print >&2 || true
  echo "attached firebreak worker smoke expected exactly two worker roots" >&2
  exit 1
fi

ordered_worker_roots=$(ls -1dt "$state_dir"/workers/*/ 2>/dev/null || true)
first_worker_root=$(printf '%s\n' "$ordered_worker_roots" | tail -n 1 | sed 's:/*$::')
latest_worker_root=$(printf '%s\n' "$ordered_worker_roots" | sed -n '1s:/*$::p')

if [ -z "$first_worker_root" ] || [ -z "$latest_worker_root" ]; then
  printf '%s\n' "$ordered_worker_roots" >&2
  echo "attached firebreak worker smoke could not determine ordered worker roots" >&2
  exit 1
fi

trace_path=$latest_worker_root/trace.log

if ! [ -s "$trace_path" ]; then
  echo "attached firebreak worker smoke expected a non-empty worker trace log" >&2
  exit 1
fi

if ! grep -F -q 'attach-foreground-start' "$trace_path"; then
  cat "$trace_path" >&2
  echo "attached firebreak worker smoke did not record attach foreground start" >&2
  exit 1
fi

if ! grep -F -q 'firebreak-command-start' "$trace_path"; then
  cat "$trace_path" >&2
  echo "attached firebreak worker smoke did not record firebreak command start" >&2
  exit 1
fi

inspect_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ inspect "$(basename "$latest_worker_root")"
)

if ! printf '%s\n' "$inspect_output" | grep -F -q '"status": "exited"'; then
  printf '%s\n' "$inspect_output" >&2
  echo "attached firebreak worker smoke expected the worker to exit after --version" >&2
  exit 1
fi

if ! printf '%s\n' "$inspect_output" | grep -F -q '"trace_path": '; then
  printf '%s\n' "$inspect_output" >&2
  echo "attached firebreak worker smoke expected reviewable trace metadata" >&2
  exit 1
fi

debug_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ debug --json
)

if ! printf '%s\n' "$debug_output" | grep -F -q '"last_trace_event": "command-exit:0"'; then
  printf '%s\n' "$debug_output" >&2
  echo "attached firebreak worker smoke expected the last trace event in debug output" >&2
  exit 1
fi

first_runtime_json=$first_worker_root/instance/.firebreak-runtime.json
latest_runtime_json=$latest_worker_root/instance/.firebreak-runtime.json
if ! [ -f "$first_runtime_json" ] || ! [ -f "$latest_runtime_json" ]; then
  printf 'first_runtime_json=%s\nlatest_runtime_json=%s\n' "$first_runtime_json" "$latest_runtime_json" >&2
  echo "attached firebreak worker smoke expected retained runtime metadata for both workers" >&2
  exit 1
fi

if grep -R -F -e 'outer-leak' -e "$smoke_tmp_dir/firebreak-worker-credential-slot-leak" "$state_dir/workers" >/dev/null 2>&1; then
  grep -R -F -n -e 'outer-leak' -e "$smoke_tmp_dir/firebreak-worker-credential-slot-leak" "$state_dir/workers" >&2 || true
  echo "attached firebreak worker smoke leaked outer Firebreak selectors into the nested worker runtime" >&2
  exit 1
fi

get_json_field() {
  json_path=$1
  field_name=$2
  python3 - "$json_path" "$field_name" <<'PY'
import json
import sys

path = sys.argv[1]
field_name = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get(field_name, ""))
PY
}

first_runner_stdout_log=$(get_json_field "$first_runtime_json" "runner_stdout_log")
latest_runner_stdout_log=$(get_json_field "$latest_runtime_json" "runner_stdout_log")

if ! [ -n "$first_runner_stdout_log" ] || ! [ -f "$first_runner_stdout_log" ]; then
  printf '%s\n' "$first_runner_stdout_log" >&2
  echo "attached firebreak worker smoke expected a retained runner stdout log for the first worker" >&2
  exit 1
fi

if ! [ -n "$latest_runner_stdout_log" ] || ! [ -f "$latest_runner_stdout_log" ]; then
  printf '%s\n' "$latest_runner_stdout_log" >&2
  echo "attached firebreak worker smoke expected a retained runner stdout log for the second worker" >&2
  exit 1
fi

if grep -F -q 'toolchain-install-start' "$first_runner_stdout_log"; then
  cat "$first_runner_stdout_log" >&2
  echo "attached firebreak worker smoke should not trigger boot-time tool installation for the packaged Codex VM" >&2
  exit 1
fi

if grep -F -q 'toolchain-install-start' "$latest_runner_stdout_log"; then
  cat "$latest_runner_stdout_log" >&2
  echo "attached firebreak worker smoke should not trigger boot-time tool installation for the packaged Codex VM" >&2
  exit 1
fi

printf '%s\n' "Firebreak attached firebreak worker smoke test passed"
