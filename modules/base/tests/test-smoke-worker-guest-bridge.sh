set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-guest-bridge.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

workspace_dir=$smoke_tmp_dir/workspace
mkdir -p "$workspace_dir"

guest_script=$workspace_dir/guest-bridge-check.sh
cat >"$guest_script" <<'EOF'
set -eu

spawn_output=$(firebreak worker spawn --kind bridge-process --workspace "$PWD")
printf '__BRIDGE_SPAWN__%s\n' "$spawn_output"

worker_id=$(SPAWN_OUTPUT="$spawn_output" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["SPAWN_OUTPUT"])["worker_id"])
PY
)
printf '__BRIDGE_ID__%s\n' "$worker_id"

show_output=$(firebreak worker show --worker-id "$worker_id")
printf '__BRIDGE_SHOW__%s\n' "$show_output"

show_backend=$(SHOW_OUTPUT="$show_output" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["SHOW_OUTPUT"])["backend"])
PY
)

if [ "$show_backend" != "process" ]; then
  echo "guest bridge smoke expected a process backend, got: $show_backend" >&2
  exit 1
fi

show_authority=$(SHOW_OUTPUT="$show_output" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["SHOW_OUTPUT"])["authority"])
PY
)

if [ "$show_authority" != "guest" ]; then
  echo "guest bridge smoke expected a guest authority, got: $show_authority" >&2
  exit 1
fi

stop_spawn_output=$(firebreak worker spawn --kind bridge-stop --workspace "$PWD")
stop_worker_id=$(STOP_SPAWN_OUTPUT="$stop_spawn_output" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["STOP_SPAWN_OUTPUT"])["worker_id"])
PY
)

stop_output=$(firebreak worker stop --worker-id "$stop_worker_id")
printf '__BRIDGE_STOP__%s\n' "$stop_output"

stop_status=$(STOP_OUTPUT="$stop_output" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["STOP_OUTPUT"])["status"])
PY
)

if [ "$stop_status" != "stopping" ] && [ "$stop_status" != "stopped" ]; then
  echo "guest bridge smoke expected a stopping or stopped worker status, got: $stop_status" >&2
  exit 1
fi

limited_spawn_output=$(firebreak worker spawn --kind bridge-limited --workspace "$PWD")
limited_worker_id=$(LIMITED_SPAWN_OUTPUT="$limited_spawn_output" python3 - <<'PY'
import json
import os

print(json.loads(os.environ["LIMITED_SPAWN_OUTPUT"])["worker_id"])
PY
)

set +e
limited_second_output=$(firebreak worker spawn --kind bridge-limited --workspace "$PWD" 2>&1)
limited_second_status=$?
set -e

if [ "$limited_second_status" -eq 0 ] || ! printf '%s\n' "$limited_second_output" | grep -F -q "reached max_instances=1"; then
  printf '%s\n' "$limited_second_output" >&2
  echo "guest bridge smoke did not enforce the worker kind max_instances limit" >&2
  exit 1
fi

firebreak worker stop --worker-id "$limited_worker_id" >/dev/null

list_output=$(firebreak worker list)
printf '__BRIDGE_LIST__%s\n' "$list_output"

if ! printf '%s\n' "$list_output" | grep -F -q "$worker_id"; then
  echo "guest bridge smoke did not list the spawned worker" >&2
  exit 1
fi

printf '%s\n' '__BRIDGE_OK__'
EOF

output=$(
  cd "$workspace_dir"
  FIREBREAK_INSTANCE_EPHEMERAL=1 @BRIDGE_VM_BIN@ "$guest_script"
)

if ! printf '%s\n' "$output" | grep -F -q '__BRIDGE_OK__'; then
  printf '%s\n' "$output" >&2
  echo "worker guest bridge smoke did not complete successfully" >&2
  exit 1
fi

printf '%s\n' "Firebreak worker guest bridge smoke test passed"
