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

spawn_process_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ spawn --backend process --kind smoke-process --workspace "$workspace_dir" -- sh -c 'printf worker-ok'
)

process_worker_id=$(printf '%s\n' "$spawn_process_output" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$process_worker_id" ]; then
  printf '%s\n' "$spawn_process_output" >&2
  echo "worker smoke did not return a process worker id" >&2
  exit 1
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  process_show_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @AGENT_BIN@ show --worker-id "$process_worker_id"
  )
  if printf '%s\n' "$process_show_output" | grep -F -q '"status": "exited"'; then
    break
  fi
  sleep 0.1
done

if ! printf '%s\n' "$process_show_output" | grep -F -q '"backend": "process"'; then
  printf '%s\n' "$process_show_output" >&2
  echo "worker smoke did not preserve the process backend in metadata" >&2
  exit 1
fi

process_stdout_path=$(printf '%s\n' "$process_show_output" | sed -n 's/.*"stdout_path": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$process_stdout_path" ] || ! [ -f "$process_stdout_path" ]; then
  printf '%s\n' "$process_show_output" >&2
  echo "worker smoke did not produce a process stdout path" >&2
  exit 1
fi

if ! grep -F -q 'worker-ok' "$process_stdout_path"; then
  cat "$process_stdout_path" >&2
  echo "worker smoke did not run the process worker command" >&2
  exit 1
fi

spawn_firebreak_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:/firebreak-worker-smoke' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ spawn --backend firebreak --kind smoke-firebreak --workspace "$workspace_dir" --package firebreak-codex -- --version
)

firebreak_worker_id=$(printf '%s\n' "$spawn_firebreak_output" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$firebreak_worker_id" ]; then
  printf '%s\n' "$spawn_firebreak_output" >&2
  echo "worker smoke did not return a firebreak worker id" >&2
  exit 1
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  firebreak_show_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @AGENT_BIN@ show --worker-id "$firebreak_worker_id"
  )
  if printf '%s\n' "$firebreak_show_output" | grep -F -q '"status": "exited"'; then
    break
  fi
  sleep 0.1
done

if ! printf '%s\n' "$firebreak_show_output" | grep -F -q '"backend": "firebreak"'; then
  printf '%s\n' "$firebreak_show_output" >&2
  echo "worker smoke did not preserve the firebreak backend in metadata" >&2
  exit 1
fi

if ! printf '%s\n' "$firebreak_show_output" | grep -F -q '"package_name": "firebreak-codex"'; then
  printf '%s\n' "$firebreak_show_output" >&2
  echo "worker smoke did not preserve the firebreak package name" >&2
  exit 1
fi

firebreak_stdout_path=$(printf '%s\n' "$firebreak_show_output" | sed -n 's/.*"stdout_path": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$firebreak_stdout_path" ] || ! [ -f "$firebreak_stdout_path" ]; then
  printf '%s\n' "$firebreak_show_output" >&2
  echo "worker smoke did not produce a firebreak stdout path" >&2
  exit 1
fi

if ! grep -F -q '__INSTALLABLE__path:/firebreak-worker-smoke#firebreak-codex' "$firebreak_stdout_path"; then
  cat "$firebreak_stdout_path" >&2
  echo "worker smoke did not route the firebreak worker through nix run" >&2
  exit 1
fi

spawn_stop_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ spawn --backend process --kind smoke-stop --workspace "$workspace_dir" -- sh -c 'sleep 30'
)

stop_worker_id=$(printf '%s\n' "$spawn_stop_output" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$stop_worker_id" ]; then
  printf '%s\n' "$spawn_stop_output" >&2
  echo "worker smoke did not return a stoppable worker id" >&2
  exit 1
fi

FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ stop --worker-id "$stop_worker_id" >/dev/null

for _ in 1 2 3 4 5 6 7 8 9 10; do
  stop_show_output=$(
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
      @AGENT_BIN@ show --worker-id "$stop_worker_id"
  )
  if printf '%s\n' "$stop_show_output" | grep -F -q '"status": "stopped"'; then
    break
  fi
  sleep 0.1
done

if ! printf '%s\n' "$stop_show_output" | grep -F -q '"status": "stopped"'; then
  printf '%s\n' "$stop_show_output" >&2
  echo "worker smoke did not report a stopped worker" >&2
  exit 1
fi

spawn_stop_all_one=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ spawn --backend process --kind smoke-stop-all-one --workspace "$workspace_dir" -- sh -c 'sleep 30'
)
stop_all_one_worker_id=$(printf '%s\n' "$spawn_stop_all_one" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$stop_all_one_worker_id" ]; then
  printf '%s\n' "$spawn_stop_all_one" >&2
  echo "worker smoke did not return the first stop --all worker id" >&2
  exit 1
fi

spawn_stop_all_two=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ spawn --backend process --kind smoke-stop-all-two --workspace "$workspace_dir" -- sh -c 'sleep 30'
)
stop_all_two_worker_id=$(printf '%s\n' "$spawn_stop_all_two" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$stop_all_two_worker_id" ]; then
  printf '%s\n' "$spawn_stop_all_two" >&2
  echo "worker smoke did not return the second stop --all worker id" >&2
  exit 1
fi

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

list_output=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ list
)

if ! printf '%s\n' "$list_output" | grep -F -q "$process_worker_id"; then
  printf '%s\n' "$list_output" >&2
  echo "worker smoke did not list the process worker" >&2
  exit 1
fi

if ! printf '%s\n' "$list_output" | grep -F -q "$firebreak_worker_id"; then
  printf '%s\n' "$list_output" >&2
  echo "worker smoke did not list the firebreak worker" >&2
  exit 1
fi

printf '%s\n' "Firebreak worker smoke test passed"
