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
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-claude-version.XXXXXX")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    echo "Firebreak nested Claude version smoke preserved artifacts under: $smoke_tmp_dir" >&2
  fi
  exit "$status"
}

trap cleanup EXIT INT TERM

state_dir=$smoke_tmp_dir/state
firebreak_state_dir=$smoke_tmp_dir/firebreak-state
workspace_dir=$smoke_tmp_dir/workspace
mkdir -p "$state_dir" "$firebreak_state_dir" "$workspace_dir"

wait_for_status() {
  worker_id=$1
  expected_status=$2
  inspect_output=""
  status_pattern=$(printf '"status": "%s"' "$expected_status")

  for _ in $(seq 1 600); do
    inspect_output=$(
      FIREBREAK_WORKER_STATE_DIR="$state_dir" \
        @TOOL_BIN@ worker inspect "$worker_id" || true
    )
    if printf '%s\n' "$inspect_output" | grep -F -q "$status_pattern"; then
      printf '%s' "$inspect_output"
      return 0
    fi
    sleep 1
  done

  printf '%s' "$inspect_output"
  return 1
}

run_version() {
  env \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_STATE_DIR="$firebreak_state_dir" \
    FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
    FIREBREAK_FLAKE_REF="path:@REPO_ROOT@" \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @TOOL_BIN@ worker run --backend firebreak --kind smoke-firebreak-claude-version --workspace "$workspace_dir" --package firebreak-claude-code --json -- --version
}

assert_version_worker() {
  run_output=$1

  worker_id=$(printf '%s\n' "$run_output" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
  if [ -z "$worker_id" ]; then
    printf '%s\n' "$run_output" >&2
    echo "nested Claude version smoke did not return a worker id" >&2
    exit 1
  fi

  inspect_output=$(wait_for_status "$worker_id" exited || true)
  if ! printf '%s\n' "$inspect_output" | grep -F -q '"status": "exited"'; then
    printf '%s\n' "$inspect_output" >&2
    echo "nested Claude version smoke expected the worker to exit after --version" >&2
    exit 1
  fi

  if ! printf '%s\n' "$inspect_output" | grep -F -q '"backend": "firebreak"'; then
    printf '%s\n' "$inspect_output" >&2
    echo "nested Claude version smoke did not preserve the firebreak backend in metadata" >&2
    exit 1
  fi

  if ! printf '%s\n' "$inspect_output" | grep -F -q '"package_name": "firebreak-claude-code"'; then
    printf '%s\n' "$inspect_output" >&2
    echo "nested Claude version smoke did not preserve the nested package name" >&2
    exit 1
  fi

  logs_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @TOOL_BIN@ worker logs "$worker_id"
  )

  if ! printf '%s\n' "$logs_output" | grep -F -q 'Claude Code'; then
    printf '%s\n' "$logs_output" >&2
    echo "nested Claude version smoke did not expose Claude version output" >&2
    exit 1
  fi

  if printf '%s\n' "$logs_output" | grep -F -q 'Failed to listen on Hostname Service Socket'; then
    printf '%s\n' "$logs_output" >&2
    echo "nested Claude version smoke regressed the trimmed local socket path" >&2
    exit 1
  fi
}

first_run_output=$(run_version)
assert_version_worker "$first_run_output"

second_run_output=$(run_version)
assert_version_worker "$second_run_output"

debug_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @TOOL_BIN@ worker debug --json
)

if ! printf '%s\n' "$debug_output" | grep -F -q '"last_trace_event": "command-exit:0"'; then
  printf '%s\n' "$debug_output" >&2
  echo "nested Claude version smoke expected a clean command-exit trace" >&2
  exit 1
fi

printf '%s\n' "Firebreak nested Claude version smoke test passed"
