set -eu

bridge_dir=@WORKER_BRIDGE_MOUNT@
worker_kinds_file=@WORKER_KINDS_FILE@
local_helper=@WORKER_LOCAL_HELPER@
local_state_dir=@WORKER_LOCAL_STATE_DIR@
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak worker run --kind KIND [--workspace PATH] [--backend BACKEND] [--package NAME] [--vm-mode MODE] [--attach] [--json] [--] COMMAND...
  firebreak worker ps [-a|--all] [--json]
  firebreak worker inspect WORKER_ID
  firebreak worker logs [--stdout|--stderr] [-f|--follow] WORKER_ID
  firebreak worker stop [--all] [--json] [WORKER_ID...]
  firebreak worker rm [--all] [--force] [--json] [WORKER_ID...]
  firebreak worker prune [--force] [--json]
EOF
  exit "${1:-1}"
}

bridge_request() {
  if ! [ -d "$bridge_dir" ]; then
    echo "Firebreak worker bridge is unavailable at $bridge_dir" >&2
    exit 1
  fi

  requests_dir=$bridge_dir/requests
  mkdir -p "$requests_dir"
  request_dir=$(mktemp -d "$requests_dir/request.XXXXXX")
  request_tmp_path=$request_dir/request.json.tmp

  REQUEST_PATH=$request_tmp_path python3 - "$@" <<'PY'
import json
import os
import sys

request_path = os.environ["REQUEST_PATH"]
with open(request_path, "w", encoding="utf-8") as handle:
    json.dump({"argv": sys.argv[1:]}, handle)
PY
  mv "$request_tmp_path" "$request_dir/request.json"

  for _ in $(seq 1 600); do
    if [ -f "$request_dir/response.exit-code" ]; then
      break
    fi
    sleep 0.1
  done

  if ! [ -f "$request_dir/response.exit-code" ]; then
    echo "timed out waiting for Firebreak worker bridge response" >&2
    exit 1
  fi

  if [ -f "$request_dir/response.stdout" ]; then
    cat "$request_dir/response.stdout"
  fi
  if [ -f "$request_dir/response.stderr" ]; then
    cat "$request_dir/response.stderr" >&2
  fi

  IFS= read -r bridge_exit_code < "$request_dir/response.exit-code" || bridge_exit_code=1
  case "$bridge_exit_code" in
    ''|*[!0-9]*)
      echo "invalid Firebreak worker bridge exit code: $bridge_exit_code" >&2
      exit 1
      ;;
  esac
  return "$bridge_exit_code"
}

bridge_request_attach() {
  if ! [ -d "$bridge_dir" ]; then
    echo "Firebreak worker bridge is unavailable at $bridge_dir" >&2
    exit 1
  fi

  requests_dir=$bridge_dir/requests
  mkdir -p "$requests_dir"
  request_dir=$(mktemp -d "$requests_dir/request.XXXXXX")
  request_tmp_path=$request_dir/request.json.tmp
  stdin_fifo=$request_dir/stdin.pipe
  stdout_fifo=$request_dir/stdout.pipe

  mkfifo "$stdin_fifo" "$stdout_fifo"

  REQUEST_PATH=$request_tmp_path STDIN_FIFO=$stdin_fifo STDOUT_FIFO=$stdout_fifo python3 - "$@" <<'PY'
import json
import os
import sys

request_path = os.environ["REQUEST_PATH"]
with open(request_path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "argv": sys.argv[1:],
            "attach": True,
            "stdin_fifo": os.environ["STDIN_FIFO"],
            "stdout_fifo": os.environ["STDOUT_FIFO"],
        },
        handle,
    )
PY

  tty_state=""
  if [ -t 0 ] && [ -t 1 ]; then
    tty_state=$(stty -g)
    stty raw -echo
  fi

  restore_tty() {
    if [ -n "$tty_state" ]; then
      stty "$tty_state" 2>/dev/null || true
    fi
  }

  cleanup_attach() {
    restore_tty
    if [ -n "${stdin_forward_pid:-}" ]; then
      kill "$stdin_forward_pid" 2>/dev/null || true
    fi
    if [ -n "${stdout_forward_pid:-}" ]; then
      kill "$stdout_forward_pid" 2>/dev/null || true
    fi
  }

  trap cleanup_attach EXIT INT TERM

  mv "$request_tmp_path" "$request_dir/request.json"

  cat <"$stdout_fifo" &
  stdout_forward_pid=$!

  cat >"$stdin_fifo" &
  stdin_forward_pid=$!

  for _ in $(seq 1 36000); do
    if [ -f "$request_dir/response.exit-code" ]; then
      break
    fi
    sleep 0.1
  done

  cleanup_attach
  trap - EXIT INT TERM

  if ! [ -f "$request_dir/response.exit-code" ]; then
    echo "timed out waiting for Firebreak worker attach response" >&2
    exit 1
  fi

  IFS= read -r bridge_exit_code < "$request_dir/response.exit-code" || bridge_exit_code=1
  restore_tty
  case "$bridge_exit_code" in
    ''|*[!0-9]*)
      echo "invalid Firebreak worker bridge exit code: $bridge_exit_code" >&2
      exit 1
      ;;
  esac
  return "$bridge_exit_code"
}

resolve_kind() {
  kind_name=$1
  [ -r "$worker_kinds_file" ] || {
    echo "Firebreak worker kinds file is unavailable: $worker_kinds_file" >&2
    exit 1
  }

  KIND_NAME=$kind_name WORKER_KINDS_FILE=$worker_kinds_file python3 - <<'PY'
import json
import os
import sys

kind_name = os.environ["KIND_NAME"]
with open(os.environ["WORKER_KINDS_FILE"], "r", encoding="utf-8") as handle:
    kinds = json.load(handle)

if kind_name not in kinds:
    print(f"unknown worker kind: {kind_name}", file=sys.stderr)
    sys.exit(1)

print(json.dumps(kinds[kind_name]))
PY
}

resolve_kind_field() {
  kind_json=$1
  field_name=$2

  KIND_JSON=$kind_json FIELD_NAME=$field_name python3 - <<'PY'
import json
import os

data = json.loads(os.environ["KIND_JSON"])
value = data.get(os.environ["FIELD_NAME"])
if value is None:
    print("")
elif isinstance(value, str):
    print(value)
else:
    print(json.dumps(value))
PY
}

merge_arrays() {
  local_json=$1
  bridge_json=$2
  LOCAL_JSON=$local_json BRIDGE_JSON=$bridge_json python3 - <<'PY'
import json
import os

local_items = json.loads(os.environ["LOCAL_JSON"])
bridge_items = json.loads(os.environ["BRIDGE_JSON"])
print(json.dumps(local_items + bridge_items, indent=2))
PY
}

append_json_item() {
  base_json=$1
  item_json=$2
  BASE_JSON=$base_json ITEM_JSON=$item_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["BASE_JSON"])
item = json.loads(os.environ["ITEM_JSON"])
items.append(item)
print(json.dumps(items))
PY
}

print_worker_ids() {
  json_input=$1
  JSON_INPUT=$json_input python3 - <<'PY'
import json
import os

value = json.loads(os.environ["JSON_INPUT"])
if isinstance(value, dict):
    worker_id = value.get("worker_id")
    if worker_id:
        print(worker_id)
else:
    for item in value:
        worker_id = item.get("worker_id")
        if worker_id:
            print(worker_id)
PY
}

print_ps_table() {
  json_input=$1
  JSON_INPUT=$json_input python3 - <<'PY'
import json
import os

items = json.loads(os.environ["JSON_INPUT"])
print(f"{'WORKER ID':<22} {'KIND':<14} {'BACKEND':<10} {'STATUS':<10} {'EXIT':<6}")
for item in items:
    exit_code = item.get("exit_code")
    print(f"{item.get('worker_id',''):<22} {item.get('kind',''):<14} {item.get('backend',''):<10} {item.get('status',''):<10} {('-' if exit_code is None else exit_code)!s:<6}")
PY
}

bridge_ps_json() {
  if ! [ -d "$bridge_dir" ]; then
    printf '%s\n' '[]'
    return 0
  fi

  if [ "${1:-}" = "--all" ]; then
    bridge_request ps --all --json
  else
    bridge_request ps --json
  fi
}

resolve_kind_max_instances() {
  kind_json=$1

  KIND_JSON=$kind_json python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["KIND_JSON"])
value = data.get("max_instances", data.get("maxInstances"))

if value is None or value == "":
    print("")
    raise SystemExit(0)

if isinstance(value, int):
    parsed = value
elif isinstance(value, str) and value.isdigit():
    parsed = int(value)
else:
    print("worker kind max_instances must be a positive integer", file=sys.stderr)
    raise SystemExit(1)

if parsed <= 0:
    print("worker kind max_instances must be greater than zero", file=sys.stderr)
    raise SystemExit(1)

print(parsed)
PY
}

count_active_workers_for_kind() {
  kind_name=$1
  local_json=$("$local_helper" ps --all --json)
  bridge_json=$(bridge_ps_json --all)

  KIND_NAME=$kind_name LOCAL_JSON=$local_json BRIDGE_JSON=$bridge_json python3 - <<'PY'
import json
import os

kind_name = os.environ["KIND_NAME"]
active_statuses = {"active", "created", "running", "stopping"}
items = json.loads(os.environ["LOCAL_JSON"]) + json.loads(os.environ["BRIDGE_JSON"])
count = 0

for item in items:
    if item.get("kind") != kind_name:
        continue
    if item.get("status") in active_statuses:
        count += 1

print(count)
PY
}

enforce_kind_limit() {
  kind_json=$1
  kind_name=$2

  max_instances=$(resolve_kind_max_instances "$kind_json")
  if [ -z "$max_instances" ]; then
    return 0
  fi

  active_count=$(count_active_workers_for_kind "$kind_name")
  if [ "$active_count" -ge "$max_instances" ]; then
    echo "worker kind '$kind_name' reached max_instances=$max_instances" >&2
    exit 1
  fi
}

local_worker_exists() {
  worker_id=$1
  [ -f "$local_state_dir/workers/$worker_id/metadata.json" ]
}

acquire_kind_spawn_lock() {
  kind_name=$1
  lock_root=$local_state_dir/spawn-locks
  kind_spawn_lock_dir=$lock_root/$kind_name.lock

  mkdir -p "$lock_root"
  while ! mkdir "$kind_spawn_lock_dir" 2>/dev/null; do
    sleep 0.1
  done
}

release_kind_spawn_lock() {
  if [ -n "${kind_spawn_lock_dir:-}" ]; then
    rmdir "$kind_spawn_lock_dir" 2>/dev/null || true
    kind_spawn_lock_dir=""
  fi
}

collect_json_results_for_ids() {
  action=$1
  shift
  action_args=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    action_args+=("$1")
    shift
  done
  if [ "${1:-}" = "--" ]; then
    shift
  fi

  json_output='[]'
  for worker_id in "$@"; do
    if local_worker_exists "$worker_id"; then
      item_json=$("$local_helper" "$action" "${action_args[@]}" --json "$worker_id")
    else
      item_json=$(bridge_request "$action" "${action_args[@]}" --json "$worker_id")
    fi
    json_output=$(append_json_item "$json_output" "$item_json")
  done
  printf '%s\n' "$json_output"
}

case "$command" in
  worker)
    shift
    ;;
  ""|help|-h|--help)
    usage 0
    ;;
  *)
    echo "unsupported guest firebreak command: $command" >&2
    usage 1
    ;;
esac

subcommand=${1:-}
case "$subcommand" in
  run)
    shift
    attach_mode=0
    backend=""
    kind=""
    workspace=$PWD
    package_name=""
    vm_mode=""
    run_json=0

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --backend)
          backend=$2
          shift 2
          ;;
        --kind)
          kind=$2
          shift 2
          ;;
        --workspace)
          workspace=$2
          shift 2
          ;;
        --package)
          package_name=$2
          shift 2
          ;;
        --vm-mode)
          vm_mode=$2
          shift 2
          ;;
        --json)
          run_json=1
          shift
          ;;
        --attach)
          attach_mode=1
          shift
          ;;
        --)
          shift
          break
          ;;
        -*)
          usage
          ;;
        *)
          break
          ;;
      esac
    done

    [ -n "$kind" ] || usage
    kind_json=$(resolve_kind "$kind")

    if [ -z "$backend" ]; then
      backend=$(resolve_kind_field "$kind_json" "backend")
    fi

    if [ "$attach_mode" = "1" ] && [ "$run_json" = "1" ]; then
      echo "firebreak worker run does not support --attach with --json" >&2
      exit 1
    fi

    acquire_kind_spawn_lock "$kind"
    trap release_kind_spawn_lock EXIT INT TERM
    enforce_kind_limit "$kind_json" "$kind"

    case "$backend" in
      process)
        if [ "$#" -eq 0 ]; then
          default_command_json=$(resolve_kind_field "$kind_json" "command")
          if [ -n "$default_command_json" ]; then
            KIND_JSON=$kind_json WORKER_LOCAL_HELPER=$local_helper WORKER_KIND=$kind WORKER_WORKSPACE=$workspace WORKER_RUN_JSON=$run_json WORKER_ATTACH_MODE=$attach_mode python3 - <<'PY'
import json
import os
import subprocess
import sys

data = json.loads(os.environ["KIND_JSON"])
command = data.get("command")
if not isinstance(command, list) or not command:
    raise SystemExit(0)

argv = [
    os.environ["WORKER_LOCAL_HELPER"],
    "run",
    "--backend",
    "process",
    "--kind",
    os.environ["WORKER_KIND"],
    "--workspace",
    os.environ["WORKER_WORKSPACE"],
]
if os.environ.get("WORKER_ATTACH_MODE") == "1":
    argv.append("--attach")
if os.environ["WORKER_RUN_JSON"] == "1":
    argv.append("--json")
argv.extend(["--", *[str(item) for item in command]])
result = subprocess.run(argv, check=False)
sys.exit(result.returncode)
PY
            run_status=$?
            release_kind_spawn_lock
            trap - EXIT INT TERM
            exit "$run_status"
          fi
        fi
        if [ "$attach_mode" = "1" ]; then
          "$local_helper" run --backend process --kind "$kind" --workspace "$workspace" --attach -- "$@"
        elif [ "$run_json" = "1" ]; then
          "$local_helper" run --backend process --kind "$kind" --workspace "$workspace" --json -- "$@"
        else
          "$local_helper" run --backend process --kind "$kind" --workspace "$workspace" -- "$@"
        fi
        run_status=$?
        release_kind_spawn_lock
        trap - EXIT INT TERM
        exit "$run_status"
        ;;
      firebreak)
        if [ -z "$package_name" ]; then
          package_name=$(resolve_kind_field "$kind_json" "package")
        fi
        if [ -z "$vm_mode" ]; then
          vm_mode=$(resolve_kind_field "$kind_json" "vm_mode")
        fi
        if [ -z "$vm_mode" ]; then
          vm_mode=run
        fi
        if [ "$attach_mode" = "1" ]; then
          bridge_request_attach run --backend firebreak --kind "$kind" --workspace "$workspace" --package "$package_name" --vm-mode "$vm_mode" --attach -- "$@"
        elif [ "$run_json" = "1" ]; then
          bridge_request run --backend firebreak --kind "$kind" --workspace "$workspace" --package "$package_name" --vm-mode "$vm_mode" --json -- "$@"
        else
          bridge_request run --backend firebreak --kind "$kind" --workspace "$workspace" --package "$package_name" --vm-mode "$vm_mode" -- "$@"
        fi
        run_status=$?
        release_kind_spawn_lock
        trap - EXIT INT TERM
        exit "$run_status"
        ;;
      *)
        release_kind_spawn_lock
        trap - EXIT INT TERM
        echo "unsupported worker backend: $backend" >&2
        exit 1
        ;;
    esac
    ;;
  ps)
    shift
    ps_all=0
    ps_json=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -a|--all)
          ps_all=1
          shift
          ;;
        --json)
          ps_json=1
          shift
          ;;
        *)
          usage
          ;;
      esac
    done
    if [ "$ps_all" = "1" ]; then
      local_json=$("$local_helper" ps --all --json)
      bridge_json=$(bridge_ps_json --all)
    else
      local_json=$("$local_helper" ps --json)
      bridge_json=$(bridge_ps_json)
    fi
    merged_json=$(merge_arrays "$local_json" "$bridge_json")
    if [ "$ps_json" = "1" ]; then
      printf '%s\n' "$merged_json"
    else
      print_ps_table "$merged_json"
    fi
    ;;
  inspect)
    shift
    [ "$#" -eq 1 ] || usage
    worker_id=$1
    if local_worker_exists "$worker_id"; then
      exec "$local_helper" inspect "$worker_id"
    fi
    bridge_request inspect "$worker_id"
    exit $?
    ;;
  logs)
    shift
    target_worker_id=""
    for arg in "$@"; do
      target_worker_id=$arg
    done
    if [ -z "$target_worker_id" ]; then
      usage
    fi
    if local_worker_exists "$target_worker_id"; then
      exec "$local_helper" logs "$@"
    fi
    bridge_request logs "$@"
    exit $?
    ;;
  stop)
    shift
    stop_all=0
    stop_json=0
    stop_ids=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --all)
          stop_all=1
          shift
          ;;
        --json)
          stop_json=1
          shift
          ;;
        -*)
          usage
          ;;
        *)
          stop_ids+=("$1")
          shift
          ;;
      esac
    done

    if [ "$stop_all" = "1" ]; then
      [ "${#stop_ids[@]}" -eq 0 ] || usage
      local_json=$("$local_helper" stop --all --json)
      if [ -d "$bridge_dir" ]; then
        bridge_json=$(bridge_request stop --all --json)
      else
        bridge_json='[]'
      fi
      merged_json=$(merge_arrays "$local_json" "$bridge_json")
      if [ "$stop_json" = "1" ]; then
        printf '%s\n' "$merged_json"
      else
        print_worker_ids "$merged_json"
      fi
      exit 0
    fi

    [ "${#stop_ids[@]}" -gt 0 ] || usage
    result_json=$(collect_json_results_for_ids stop -- "${stop_ids[@]}")
    if [ "$stop_json" = "1" ]; then
      if [ "${#stop_ids[@]}" -eq 1 ]; then
        RESULT_JSON=$result_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["RESULT_JSON"])
print(json.dumps(items[0], indent=2))
PY
      else
        printf '%s\n' "$result_json"
      fi
    else
      print_worker_ids "$result_json"
    fi
    ;;
  rm)
    shift
    rm_all=0
    rm_force=0
    rm_json=0
    rm_ids=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --all)
          rm_all=1
          shift
          ;;
        --force)
          rm_force=1
          shift
          ;;
        --json)
          rm_json=1
          shift
          ;;
        -*)
          usage
          ;;
        *)
          rm_ids+=("$1")
          shift
          ;;
      esac
    done

    if [ "$rm_all" = "1" ]; then
      [ "${#rm_ids[@]}" -eq 0 ] || usage
      if [ "$rm_force" = "1" ]; then
        local_json=$("$local_helper" rm --all --force --json)
        if [ -d "$bridge_dir" ]; then
          bridge_json=$(bridge_request rm --all --force --json)
        else
          bridge_json='[]'
        fi
      else
        local_json=$("$local_helper" rm --all --json)
        if [ -d "$bridge_dir" ]; then
          bridge_json=$(bridge_request rm --all --json)
        else
          bridge_json='[]'
        fi
      fi
      merged_json=$(merge_arrays "$local_json" "$bridge_json")
      if [ "$rm_json" = "1" ]; then
        printf '%s\n' "$merged_json"
      else
        print_worker_ids "$merged_json"
      fi
      exit 0
    fi

    [ "${#rm_ids[@]}" -gt 0 ] || usage
    if [ "$rm_force" = "1" ]; then
      result_json=$(collect_json_results_for_ids rm --force -- "${rm_ids[@]}")
    else
      result_json=$(collect_json_results_for_ids rm -- "${rm_ids[@]}")
    fi
    if [ "$rm_json" = "1" ]; then
      if [ "${#rm_ids[@]}" -eq 1 ]; then
        RESULT_JSON=$result_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["RESULT_JSON"])
print(json.dumps(items[0], indent=2))
PY
      else
        printf '%s\n' "$result_json"
      fi
    else
      print_worker_ids "$result_json"
    fi
    ;;
  prune)
    shift
    prune_force=0
    prune_json=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --force)
          prune_force=1
          shift
          ;;
        --json)
          prune_json=1
          shift
          ;;
        *)
          usage
          ;;
      esac
    done

    if [ "$prune_force" = "1" ]; then
      local_json=$("$local_helper" prune --force --json)
      if [ -d "$bridge_dir" ]; then
        bridge_json=$(bridge_request prune --force --json)
      else
        bridge_json='[]'
      fi
    else
      local_json=$("$local_helper" prune --json)
      if [ -d "$bridge_dir" ]; then
        bridge_json=$(bridge_request prune --json)
      else
        bridge_json='[]'
      fi
    fi
    merged_json=$(merge_arrays "$local_json" "$bridge_json")
    if [ "$prune_json" = "1" ]; then
      printf '%s\n' "$merged_json"
    else
      print_worker_ids "$merged_json"
    fi
    ;;
  ""|help|-h|--help)
    usage 0
    ;;
  *)
    echo "unknown firebreak worker subcommand: $subcommand" >&2
    exit 1
    ;;
esac
