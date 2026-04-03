#!/usr/bin/env bash
set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

wait_for_status() {
  worker_id=$1
  expected_status=$2
  inspect_output=""
  status_pattern=$(printf '"status": "%s"' "$expected_status")

  for _ in $(seq 1 100); do
    inspect_output=$(
      FIREBREAK_WORKER_STATE_DIR="$state_dir" \
        @AGENT_BIN@ inspect "$worker_id"
    )
    if printf '%s\n' "$inspect_output" | grep -F -q "$status_pattern"; then
      printf '%s' "$inspect_output"
      return 0
    fi
    sleep 0.1
  done

  printf '%s' "$inspect_output"
  return 1
}

wait_for_worker_id_by_kind() {
  kind_prefix=$1

  for _ in $(seq 1 100); do
    for candidate_root in "$state_dir"/workers/"$kind_prefix"-*; do
      [ -d "$candidate_root" ] || continue
      basename "$candidate_root"
      return 0
    done
    sleep 0.1
  done

  return 1
}

state_dir=$smoke_tmp_dir/state
workspace_dir=$smoke_tmp_dir/workspace
fake_bin_dir=$smoke_tmp_dir/bin
fake_nix_store_dir=$smoke_tmp_dir/fake-nix-store
mkdir -p "$state_dir" "$workspace_dir" "$fake_bin_dir" "$fake_nix_store_dir"
export FAKE_NIX_STORE_DIR="$fake_nix_store_dir"

# shellcheck disable=SC2154
cat >"$fake_bin_dir/nix" <<'EOF'
#!/usr/bin/env bash
set -eu

if [ "${1:-}" = "--version" ]; then
  printf '%s\n' 'nix smoke shim'
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    build|run)
      command=$1
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

[ -n "${command:-}" ] || exit 1
if [ "$command" = "build" ]; then
  while [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; do
    shift
  done
fi
[ "$#" -gt 0 ] || exit 1
installable=${1:-}
shift

if [ "$command" = "build" ]; then
  package_name=${installable##*#}
  fake_out="$FAKE_NIX_STORE_DIR/$package_name"
  mkdir -p "$fake_out/bin"
  cat >"$fake_out/bin/$package_name" <<SCRIPT
#!/usr/bin/env bash
set -eu
printf '%s\n' "__INSTALLABLE__$installable"
printf '%s\n' "__SESSION_MODE__\${FIREBREAK_AGENT_SESSION_MODE_OVERRIDE:-}"
if [ "\${1:-}" = "__sleep__" ]; then
  shift
  trap 'exit 0' TERM INT
  while :; do
    sleep 1
  done
fi
for arg in "\$@"; do
  printf '%s\n' "__ARG__\$arg"
done
SCRIPT
  chmod +x "$fake_out/bin/$package_name"
  printf '%s\n' "$fake_out"
  exit 0
fi

if [ "${1:-}" = "--" ]; then
  shift
fi

printf '%s\n' "__INSTALLABLE__$installable"
printf '%s\n' "__SESSION_MODE__${FIREBREAK_AGENT_SESSION_MODE_OVERRIDE:-}"
for arg in "$@"; do
  printf '%s\n' "__ARG__$arg"
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

process_inspect_output=$(wait_for_status "$process_worker_id" exited || true)

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

attach_firebreak_default_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:@REPO_ROOT@' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --attach --backend firebreak --kind smoke-firebreak-attach-default --workspace "$workspace_dir" --package firebreak-codex
)

if ! printf '%s\n' "$attach_firebreak_default_output" | grep -F -q '__SESSION_MODE__agent-attach-exec'; then
  printf '%s\n' "$attach_firebreak_default_output" >&2
  echo "worker smoke did not force attached firebreak workers into agent-attach-exec mode" >&2
  exit 1
fi

attach_firebreak_args_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:@REPO_ROOT@' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --attach --backend firebreak --kind smoke-firebreak-attach-args --workspace "$workspace_dir" --package firebreak-codex -- --version
)

if ! printf '%s\n' "$attach_firebreak_args_output" | grep -F -q '__SESSION_MODE__agent-attach-exec'; then
  printf '%s\n' "$attach_firebreak_args_output" >&2
  echo "worker smoke did not preserve agent-attach-exec mode when attached firebreak workers forwarded args" >&2
  exit 1
fi

if ! printf '%s\n' "$attach_firebreak_args_output" | grep -F -q '__ARG__--version'; then
  printf '%s\n' "$attach_firebreak_args_output" >&2
  echo "worker smoke did not forward attached firebreak worker arguments" >&2
  exit 1
fi

spawn_firebreak_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:@REPO_ROOT@' \
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

firebreak_inspect_output=$(wait_for_status "$firebreak_worker_id" exited || true)

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
if ! printf '%s\n' "$firebreak_logs_output" | grep -F -q '__INSTALLABLE__path:@REPO_ROOT@#firebreak-codex'; then
  printf '%s\n' "$firebreak_logs_output" >&2
  echo "worker smoke did not route the firebreak worker through nix run" >&2
  exit 1
fi

attach_limit_output_path=$smoke_tmp_dir/firebreak-attach-limit.out
attach_limit_error_path=$smoke_tmp_dir/firebreak-attach-limit.err
(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:@REPO_ROOT@' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --attach --backend firebreak --kind smoke-firebreak-attach-limit --workspace "$workspace_dir" --package firebreak-codex --max-instances 1 -- __sleep__
) >"$attach_limit_output_path" 2>"$attach_limit_error_path" &
attach_limit_pid=$!

attach_limit_worker_id=$(wait_for_worker_id_by_kind smoke-firebreak-attach-limit || true)
if [ -z "$attach_limit_worker_id" ]; then
  cat "$attach_limit_output_path" >&2 || true
  cat "$attach_limit_error_path" >&2 || true
  echo "worker smoke did not publish an attached firebreak worker id before enforcing max_instances" >&2
  exit 1
fi

attach_limit_running_output=$(wait_for_status "$attach_limit_worker_id" running || true)
if ! printf '%s\n' "$attach_limit_running_output" | grep -F -q '"status": "running"'; then
  printf '%s\n' "$attach_limit_running_output" >&2
  echo "worker smoke did not report the first attached firebreak worker as running" >&2
  exit 1
fi

set +e
attach_limit_second_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:@REPO_ROOT@' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --attach --backend firebreak --kind smoke-firebreak-attach-limit --workspace "$workspace_dir" --package firebreak-codex --max-instances 1 -- __sleep__ 2>&1
)
attach_limit_second_status=$?
set -e

if [ "$attach_limit_second_status" -eq 0 ] || ! printf '%s\n' "$attach_limit_second_output" | grep -F -q "reached max_instances=1"; then
  printf '%s\n' "$attach_limit_second_output" >&2
  echo "worker smoke did not enforce max_instances for attached firebreak workers" >&2
  exit 1
fi

FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ stop "$attach_limit_worker_id" >/dev/null
set +e
wait "$attach_limit_pid"
set -e

attach_limit_stopped_output=$(wait_for_status "$attach_limit_worker_id" stopped || true)
if ! printf '%s\n' "$attach_limit_stopped_output" | grep -F -q '"status": "stopped"'; then
  printf '%s\n' "$attach_limit_stopped_output" >&2
  echo "worker smoke did not stop an attached firebreak worker cleanly" >&2
  exit 1
fi

scoped_limit_first_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:@REPO_ROOT@' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --backend firebreak --kind smoke-firebreak-scoped-limit --workspace "$workspace_dir" --package firebreak-codex --max-instances 1 --json -- __sleep__
)

scoped_limit_first_id=$(printf '%s\n' "$scoped_limit_first_output" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$scoped_limit_first_id" ]; then
  printf '%s\n' "$scoped_limit_first_output" >&2
  echo "worker smoke did not return the first scoped-limit firebreak worker id" >&2
  exit 1
fi

scoped_limit_first_running=$(wait_for_status "$scoped_limit_first_id" running || true)
if ! printf '%s\n' "$scoped_limit_first_running" | grep -F -q '"status": "running"'; then
  printf '%s\n' "$scoped_limit_first_running" >&2
  echo "worker smoke did not report the first scoped-limit firebreak worker as running" >&2
  exit 1
fi

scoped_limit_second_output=$(
  PATH="$fake_bin_dir:$PATH" \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_FLAKE_REF='path:/alternate-firebreak-recipe' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1 \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    @AGENT_BIN@ run --backend firebreak --kind smoke-firebreak-scoped-limit --workspace "$workspace_dir" --package firebreak-codex --max-instances 1 --json -- __sleep__
)

scoped_limit_second_id=$(printf '%s\n' "$scoped_limit_second_output" | sed -n 's/.*"worker_id": "\([^"]*\)".*/\1/p' | head -n 1)
if [ -z "$scoped_limit_second_id" ]; then
  printf '%s\n' "$scoped_limit_second_output" >&2
  echo "worker smoke incorrectly shared max_instances across different firebreak recipes" >&2
  exit 1
fi

scoped_limit_second_running=$(wait_for_status "$scoped_limit_second_id" running || true)
if ! printf '%s\n' "$scoped_limit_second_running" | grep -F -q '"status": "running"'; then
  printf '%s\n' "$scoped_limit_second_running" >&2
  echo "worker smoke did not report the second scoped-limit firebreak worker as running" >&2
  exit 1
fi

FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ stop "$scoped_limit_first_id" "$scoped_limit_second_id" >/dev/null

stop_worker_id=$(
  FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    @AGENT_BIN@ run --backend process --kind smoke-stop --workspace "$workspace_dir" -- sh -c 'sleep 30'
)

FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ stop "$stop_worker_id" >/dev/null

stop_inspect_output=$(wait_for_status "$stop_worker_id" stopped || true)

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

if ! printf '%s\n' "$debug_output" | grep -F -q '"last_trace_event": "command-exit:0"'; then
  printf '%s\n' "$debug_output" >&2
  echo "worker smoke debug did not include the last trace event" >&2
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

if ! printf '%s\n' "$debug_text_output" | grep -F -q 'last_trace_event:'; then
  printf '%s\n' "$debug_text_output" >&2
  echo "worker smoke debug text output did not include worker detail diagnostics" >&2
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
