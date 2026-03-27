set -eu

default_firebreak_tmpdir=${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}
if [ -d /cache ] && [ -w /cache ]; then
  default_firebreak_tmpdir=/cache/firebreak
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-$default_firebreak_tmpdir}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-firebreak-attach.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

state_dir=$smoke_tmp_dir/state
workspace_dir=$smoke_tmp_dir/workspace
mkdir -p "$state_dir" "$workspace_dir"

attach_output=$(
  env \
    AGENT_CONFIG=outer-leak \
    AGENT_CONFIG_HOST_PATH=/tmp/firebreak-worker-attach-leak \
    CODEX_CONFIG=outer-leak \
    CODEX_CONFIG_HOST_PATH=/tmp/firebreak-worker-codex-attach-leak \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF="path:@REPO_ROOT@" \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --attach --backend firebreak --kind smoke-firebreak-attach --workspace "$workspace_dir" --package firebreak-codex -- --version
)

if ! printf '%s\n' "$attach_output" | grep -F -q 'codex-cli'; then
  printf '%s\n' "$attach_output" >&2
  echo "attached firebreak worker smoke did not expose codex version output" >&2
  exit 1
fi

worker_count=$(find "$state_dir/workers" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$worker_count" != "1" ]; then
  find "$state_dir/workers" -mindepth 1 -maxdepth 1 -type d -print >&2 || true
  echo "attached firebreak worker smoke expected exactly one worker root" >&2
  exit 1
fi

worker_root=$(find "$state_dir/workers" -mindepth 1 -maxdepth 1 -type d | head -n 1)
trace_path=$worker_root/trace.log

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
    @AGENT_BIN@ inspect "$(basename "$worker_root")"
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

printf '%s\n' "Firebreak attached firebreak worker smoke test passed"
