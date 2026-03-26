set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

state_dir=$smoke_tmp_dir/state
workspace_dir=$smoke_tmp_dir/workspace
fake_bin_dir=$smoke_tmp_dir/bin
mkdir -p "$state_dir" "$workspace_dir" "$fake_bin_dir"

cat >"$fake_bin_dir/nix" <<EOF
#!/usr/bin/env bash
set -eu

if [ "\${1:-}" = "--version" ]; then
  printf '%s\n' 'nix smoke shim'
  exit 0
fi

while [ "\$#" -gt 0 ] && [ "\$1" != "run" ]; do
  shift
done

[ "\$#" -gt 0 ] || exit 1
shift
installable=\${1:-}
shift

if [ "\${1:-}" = "--" ]; then
  shift
fi

printf '%s\n' "__INSTALLABLE__\$installable"
for arg in "\$@"; do
  printf '%s\n' "__ARG__\$arg"
done
EOF
chmod +x "$fake_bin_dir/nix"

process_worker_id=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --backend process --kind smoke-process --workspace "$workspace_dir" -- sh -c 'printf worker-ok'
)

if [ -z "$process_worker_id" ]; then
  echo "worker smoke did not return a process worker id" >&2
  exit 1
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  process_inspect_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @AGENT_BIN@ inspect "$process_worker_id"
  )
  if printf '%s\n' "$process_inspect_output" | grep -F -q '"status": "exited"'; then
    break
  fi
  sleep 0.1
done

if ! printf '%s\n' "$process_inspect_output" | grep -F -q '"backend": "process"'; then
  printf '%s\n' "$process_inspect_output" >&2
  echo "worker smoke did not preserve the process backend in metadata" >&2
  exit 1
fi

process_logs_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ logs "$process_worker_id"
)
if ! printf '%s\n' "$process_logs_output" | grep -F -q 'worker-ok'; then
  printf '%s\n' "$process_logs_output" >&2
  echo "worker smoke did not expose process worker logs" >&2
  exit 1
fi

attach_process_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --attach --backend process --kind smoke-attach-process --workspace "$workspace_dir" -- sh -c 'printf attached-ok'
)
if ! printf '%s\n' "$attach_process_output" | grep -F -q 'attached-ok'; then
  printf '%s\n' "$attach_process_output" >&2
  echo "worker smoke did not expose attached process output" >&2
  exit 1
fi

spawn_firebreak_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:/firebreak-worker-smoke' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --backend firebreak --kind smoke-firebreak --workspace "$workspace_dir" --package firebreak-codex --json -- --version
)

firebreak_worker_id=$(printf '%s\n' "$spawn_firebreak_output" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$firebreak_worker_id" ]; then
  printf '%s\n' "$spawn_firebreak_output" >&2
  echo "worker smoke did not return a firebreak worker id" >&2
  exit 1
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  firebreak_inspect_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @AGENT_BIN@ inspect "$firebreak_worker_id"
  )
  if printf '%s\n' "$firebreak_inspect_output" | grep -F -q '"status": "exited"'; then
    break
  fi
  sleep 0.1
done

if ! printf '%s\n' "$firebreak_inspect_output" | grep -F -q '"backend": "firebreak"'; then
  printf '%s\n' "$firebreak_inspect_output" >&2
  echo "worker smoke did not preserve the firebreak backend in metadata" >&2
  exit 1
fi

if ! printf '%s\n' "$firebreak_inspect_output" | grep -F -q '"package_name": "firebreak-codex"'; then
  printf '%s\n' "$firebreak_inspect_output" >&2
  echo "worker smoke did not preserve the firebreak package name" >&2
  exit 1
fi

firebreak_logs_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ logs "$firebreak_worker_id"
)
if ! printf '%s\n' "$firebreak_logs_output" | grep -F -q '__INSTALLABLE__path:/firebreak-worker-smoke#firebreak-codex'; then
  printf '%s\n' "$firebreak_logs_output" >&2
  echo "worker smoke did not route the firebreak worker through nix run" >&2
  exit 1
fi

stop_worker_id=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --backend process --kind smoke-stop --workspace "$workspace_dir" -- sh -c 'sleep 30'
)

FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ stop "$stop_worker_id" >/dev/null

for _ in 1 2 3 4 5 6 7 8 9 10; do
  stop_inspect_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @AGENT_BIN@ inspect "$stop_worker_id"
  )
  if printf '%s\n' "$stop_inspect_output" | grep -F -q '"status": "stopped"'; then
    break
  fi
  sleep 0.1
done

if ! printf '%s\n' "$stop_inspect_output" | grep -F -q '"status": "stopped"'; then
  printf '%s\n' "$stop_inspect_output" >&2
  echo "worker smoke did not report a stopped worker" >&2
  exit 1
fi

stop_all_one_worker_id=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --backend process --kind smoke-stop-all-one --workspace "$workspace_dir" -- sh -c 'sleep 30'
)
stop_all_two_worker_id=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --backend process --kind smoke-stop-all-two --workspace "$workspace_dir" -- sh -c 'sleep 30'
)

stop_all_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ stop --all
)

if ! printf '%s\n' "$stop_all_output" | grep -F -q "$stop_all_one_worker_id"; then
  printf '%s\n' "$stop_all_output" >&2
  echo "worker smoke stop --all did not include the first running worker" >&2
  exit 1
fi

if ! printf '%s\n' "$stop_all_output" | grep -F -q "$stop_all_two_worker_id"; then
  printf '%s\n' "$stop_all_output" >&2
  echo "worker smoke stop --all did not include the second running worker" >&2
  exit 1
fi

ps_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ ps -a
)

if ! printf '%s\n' "$ps_output" | grep -F -q "$process_worker_id"; then
  printf '%s\n' "$ps_output" >&2
  echo "worker smoke did not list the process worker" >&2
  exit 1
fi

if ! printf '%s\n' "$ps_output" | grep -F -q "$firebreak_worker_id"; then
  printf '%s\n' "$ps_output" >&2
  echo "worker smoke did not list the firebreak worker" >&2
  exit 1
fi

debug_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ debug --json
)

if ! printf '%s\n' "$debug_output" | grep -F -q "\"state_dir\": \"$state_dir\""; then
  printf '%s\n' "$debug_output" >&2
  echo "worker smoke debug did not report the worker state dir" >&2
  exit 1
fi

if ! printf '%s\n' "$debug_output" | grep -F -q "\"worker_id\": \"$firebreak_worker_id\""; then
  printf '%s\n' "$debug_output" >&2
  echo "worker smoke debug did not include the firebreak worker" >&2
  exit 1
fi

debug_text_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ debug
)

if ! printf '%s\n' "$debug_text_output" | grep -F -q 'Firebreak worker broker'; then
  printf '%s\n' "$debug_text_output" >&2
  echo "worker smoke debug text output did not include the header" >&2
  exit 1
fi

if ! printf '%s\n' "$debug_text_output" | grep -F -q "$firebreak_worker_id"; then
  printf '%s\n' "$debug_text_output" >&2
  echo "worker smoke debug text output did not include the firebreak worker" >&2
  exit 1
fi

rm_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ rm "$process_worker_id"
)
if ! printf '%s\n' "$rm_output" | grep -F -q "$process_worker_id"; then
  printf '%s\n' "$rm_output" >&2
  echo "worker smoke did not remove a stopped worker" >&2
  exit 1
fi

force_rm_worker_id=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --backend process --kind smoke-force-rm --workspace "$workspace_dir" -- sh -c 'sleep 30'
)

force_rm_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ rm --force "$force_rm_worker_id"
)
if ! printf '%s\n' "$force_rm_output" | grep -F -q "$force_rm_worker_id"; then
  printf '%s\n' "$force_rm_output" >&2
  echo "worker smoke did not force-remove a running worker" >&2
  exit 1
fi

prune_target_id=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --backend process --kind smoke-prune --workspace "$workspace_dir" -- sh -c 'printf prune-ok'
)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  prune_inspect_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @AGENT_BIN@ inspect "$prune_target_id"
  )
  if printf '%s\n' "$prune_inspect_output" | grep -F -q '"status": "exited"'; then
    break
  fi
  sleep 0.1
done

prune_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ prune
)
if ! printf '%s\n' "$prune_output" | grep -F -q "$prune_target_id"; then
  printf '%s\n' "$prune_output" >&2
  echo "worker smoke did not prune an exited worker" >&2
  exit 1
fi

printf '%s\n' "Firebreak worker smoke test passed"
