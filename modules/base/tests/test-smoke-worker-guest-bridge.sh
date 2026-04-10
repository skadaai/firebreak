#!/usr/bin/env bash
set -eu

# shellcheck disable=SC1091
. "@REPO_ROOT@/modules/base/host/firebreak-project-config.sh"

default_firebreak_tmpdir=${TMPDIR:-/tmp}
if [ -d /cache ] && [ -w /cache ]; then
  default_firebreak_tmpdir=/cache/firebreak
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-$default_firebreak_tmpdir}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-guest-bridge.XXXXXX")
keep_smoke_tmp_dir=0
cleanup() {
  if [ "$keep_smoke_tmp_dir" = "1" ]; then
    printf '%s\n' "preserved worker guest bridge smoke artifacts: $smoke_tmp_dir" >&2
    return
  fi
  rm -rf "$smoke_tmp_dir"
}
trap cleanup EXIT INT TERM

workspace_dir=$smoke_tmp_dir/workspace
state_dir=$smoke_tmp_dir/state
firebreak_state_dir=$smoke_tmp_dir/firebreak-state
mkdir -p "$workspace_dir" "$state_dir" "$firebreak_state_dir"

run_with_clean_firebreak_env() (
  while IFS= read -r env_key; do
    [ -n "$env_key" ] || continue
    unset "$env_key"
  done <<EOF
$(firebreak_list_scrubbable_env_keys)
EOF

  while [ "$#" -gt 0 ]; do
    case "$1" in
      *=*)
        assignment=$1
        export "${assignment%%=*}=${assignment#*=}"
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  exec "$@"
)

guest_script=$workspace_dir/guest-bridge-check.sh
cat >"$guest_script" <<'INNER_EOF'
set -eu

guest_system_bin=/run/current-system/sw/bin
firebreak_bin=$guest_system_bin/firebreak
python3_bin=$guest_system_bin/python3

if ! [ -x "$firebreak_bin" ]; then
  echo "guest bridge smoke missing firebreak CLI at $firebreak_bin" >&2
  exit 1
fi

if ! [ -x "$python3_bin" ]; then
  echo "guest bridge smoke missing python3 at $python3_bin" >&2
  exit 1
fi

stale_lock_dir=@WORKER_LOCAL_STATE_DIR@/spawn-locks/bridge-process.lock
mkdir -p "$stale_lock_dir"
printf '%s\n' 999999 >"$stale_lock_dir/pid"

spawn_output=$("$firebreak_bin" worker run --kind bridge-process --workspace "$PWD" --json)
printf '__BRIDGE_SPAWN__%s\n' "$spawn_output"

worker_id=$(RUN_OUTPUT="$spawn_output" "$python3_bin" - <<'PY'
import json
import os

print(json.loads(os.environ["RUN_OUTPUT"])["worker_id"])
PY
)
printf '__BRIDGE_ID__%s\n' "$worker_id"

show_output=$("$firebreak_bin" worker inspect "$worker_id")
printf '__BRIDGE_SHOW__%s\n' "$show_output"

show_backend=$(SHOW_OUTPUT="$show_output" "$python3_bin" - <<'PY'
import json
import os

print(json.loads(os.environ["SHOW_OUTPUT"])["backend"])
PY
)

if [ "$show_backend" != "process" ]; then
  echo "guest bridge smoke expected a process backend, got: $show_backend" >&2
  exit 1
fi

show_authority=$(SHOW_OUTPUT="$show_output" "$python3_bin" - <<'PY'
import json
import os

print(json.loads(os.environ["SHOW_OUTPUT"])["authority"])
PY
)

if [ "$show_authority" != "guest" ]; then
  echo "guest bridge smoke expected a guest authority, got: $show_authority" >&2
  exit 1
fi

debug_output=$("$firebreak_bin" worker debug --json)
printf '__BRIDGE_DEBUG__%s\n' "$debug_output"

if ! printf '%s\n' "$debug_output" | grep -F -q '"bridge"'; then
  printf '%s\n' "$debug_output" >&2
  echo "guest bridge smoke did not expose host bridge diagnostics" >&2
  exit 1
fi

if ! printf '%s\n' "$debug_output" | grep -F -q "$worker_id"; then
  printf '%s\n' "$debug_output" >&2
  echo "guest bridge smoke debug did not include the guest worker id" >&2
  exit 1
fi

stop_spawn_output=$("$firebreak_bin" worker run --kind bridge-stop --workspace "$PWD" --json)
printf '%s\n' '__BRIDGE_STOP_SPAWNED__'
stop_worker_id=$(STOP_RUN_OUTPUT="$stop_spawn_output" "$python3_bin" - <<'PY'
import json
import os

print(json.loads(os.environ["STOP_RUN_OUTPUT"])["worker_id"])
PY
)

stop_output=$("$firebreak_bin" worker stop --json "$stop_worker_id")
printf '__BRIDGE_STOP__%s\n' "$stop_output"

stop_status=$(STOP_OUTPUT="$stop_output" "$python3_bin" - <<'PY'
import json
import os

print(json.loads(os.environ["STOP_OUTPUT"])["status"])
PY
)

if [ "$stop_status" != "stopping" ] && [ "$stop_status" != "stopped" ]; then
  echo "guest bridge smoke expected a stopping or stopped worker status, got: $stop_status" >&2
  exit 1
fi

attach_parallel_dir=$(mktemp -d "$PWD/bridge-attach-parallel.XXXXXX")
SECONDS=0
single_attach_output=$("$firebreak_bin" worker run --kind bridge-process --workspace "$PWD" --attach -- sh -c 'sleep 3; printf attach-baseline')
single_attach_elapsed=$SECONDS
printf '__BRIDGE_ATTACH_SINGLE_ELAPSED__%s\n' "$single_attach_elapsed"

if ! printf '%s\n' "$single_attach_output" | grep -F -q 'attach-baseline'; then
  printf '%s\n' "$single_attach_output" >&2
  echo "guest bridge smoke baseline attached process worker did not complete successfully" >&2
  exit 1
fi

SECONDS=0
(
  "$firebreak_bin" worker run --kind bridge-process --workspace "$PWD" --attach -- sh -c 'sleep 3; printf attach-one'
) >"$attach_parallel_dir/one.out" &
attach_parallel_one_pid=$!
(
  "$firebreak_bin" worker run --kind bridge-process --workspace "$PWD" --attach -- sh -c 'sleep 3; printf attach-two'
) >"$attach_parallel_dir/two.out" &
attach_parallel_two_pid=$!

wait "$attach_parallel_one_pid"
wait "$attach_parallel_two_pid"

attach_parallel_elapsed=$SECONDS
printf '__BRIDGE_ATTACH_PARALLEL_ELAPSED__%s\n' "$attach_parallel_elapsed"

if ! grep -F -q 'attach-one' "$attach_parallel_dir/one.out"; then
  cat "$attach_parallel_dir/one.out" >&2
  echo "guest bridge smoke first attached process worker did not complete successfully" >&2
  exit 1
fi

if ! grep -F -q 'attach-two' "$attach_parallel_dir/two.out"; then
  cat "$attach_parallel_dir/two.out" >&2
  echo "guest bridge smoke second attached process worker did not complete successfully" >&2
  exit 1
fi

serialized_threshold=$((single_attach_elapsed * 2 - 1))
minimum_parallel_threshold=$((single_attach_elapsed + 1))
if [ "$serialized_threshold" -lt "$minimum_parallel_threshold" ]; then
  serialized_threshold=$minimum_parallel_threshold
fi

if [ "$attach_parallel_elapsed" -gt "$serialized_threshold" ]; then
  echo "parallel attached process workers took too long: ${attach_parallel_elapsed}s (single attached process took ${single_attach_elapsed}s)" >&2
  exit 1
fi

printf '%s\n' '__BRIDGE_ATTACH_START__'
attach_output=$("$firebreak_bin" worker run --kind bridge-firebreak --workspace "$PWD" --attach -- --version)
printf '__BRIDGE_ATTACH__%s\n' "$attach_output"

if ! printf '%s\n' "$attach_output" | grep -F -q 'bridge-firebreak-ok'; then
  printf '%s\n' "$attach_output" >&2
  echo "guest bridge smoke did not expose attached firebreak worker output" >&2
  exit 1
fi

if ! printf '%s\n' "$attach_output" | grep -F -q 'arg:--version'; then
  printf '%s\n' "$attach_output" >&2
  echo "guest bridge smoke did not preserve forwarded firebreak worker arguments" >&2
  exit 1
fi


printf '%s\n' '__BRIDGE_OK__'
INNER_EOF

if ! output=$(
  cd "$workspace_dir"
  run_with_clean_firebreak_env \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_STATE_DIR="$firebreak_state_dir" \
    FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
    FIREBREAK_INSTANCE_EPHEMERAL=1 \
    timeout 600 @BRIDGE_VM_BIN@ "$guest_script" 2>&1
); then
  keep_smoke_tmp_dir=1
  printf '%s\n' "$output" >&2
  printf '%s\n' '--- host worker debug --json ---' >&2
  FIREBREAK_WORKER_STATE_DIR="$state_dir" @TOOL_BIN@ worker debug --json >&2 || true
  echo "worker guest bridge smoke VM run failed" >&2
  exit 1
fi

printf '%s\n' "$output"

if ! printf '%s\n' "$output" | grep -F -q '__BRIDGE_OK__'; then
  keep_smoke_tmp_dir=1
  printf '%s\n' "$output" >&2
  printf '%s\n' '--- host worker debug --json ---' >&2
  FIREBREAK_WORKER_STATE_DIR="$state_dir" @TOOL_BIN@ worker debug --json >&2 || true
  echo "worker guest bridge smoke did not complete successfully" >&2
  exit 1
fi

printf '%s\n' "Firebreak worker guest bridge smoke test passed"
