set -eu

bridge_dir=@WORKER_BRIDGE_MOUNT@
worker_kinds_file=@WORKER_KINDS_FILE@
local_helper=@WORKER_LOCAL_HELPER@
local_state_dir=@WORKER_LOCAL_STATE_DIR@
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak worker spawn --kind KIND [--workspace PATH] [--backend BACKEND] [--package NAME] [--vm-mode MODE] [--] COMMAND...
  firebreak worker list
  firebreak worker show --worker-id ID
  firebreak worker stop --worker-id ID
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

merge_lists() {
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

local_worker_exists() {
  worker_id=$1
  [ -f "$local_state_dir/workers/$worker_id/metadata.json" ]
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
  spawn)
    shift
    backend=""
    kind=""
    workspace=$PWD
    package_name=""
    vm_mode=""

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

    case "$backend" in
      process)
        if [ "$#" -eq 0 ]; then
          default_command_json=$(resolve_kind_field "$kind_json" "command")
          if [ -n "$default_command_json" ]; then
            KIND_JSON=$kind_json WORKER_LOCAL_HELPER=$local_helper WORKER_KIND=$kind WORKER_WORKSPACE=$workspace python3 - <<'PY'
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
    "spawn",
    "--backend",
    "process",
    "--kind",
    os.environ["WORKER_KIND"],
    "--workspace",
    os.environ["WORKER_WORKSPACE"],
    "--",
    *[str(item) for item in command],
]
result = subprocess.run(argv, check=False)
sys.exit(result.returncode)
PY
            exit $?
          fi
        fi
        exec "$local_helper" spawn --backend process --kind "$kind" --workspace "$workspace" -- "$@"
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
        bridge_request spawn --backend firebreak --kind "$kind" --workspace "$workspace" --package "$package_name" --vm-mode "$vm_mode" -- "$@"
        exit $?
        ;;
      *)
        echo "unsupported worker backend: $backend" >&2
        exit 1
        ;;
    esac
    ;;
  list)
    shift
    [ "$#" -eq 0 ] || usage
    local_json=$("$local_helper" list)
    bridge_json=$(bridge_request list)
    merge_lists "$local_json" "$bridge_json"
    ;;
  show)
    shift
    [ "$#" -eq 2 ] || usage
    [ "$1" = "--worker-id" ] || usage
    worker_id=$2
    if local_worker_exists "$worker_id"; then
      exec "$local_helper" show --worker-id "$worker_id"
    fi
    bridge_request show --worker-id "$worker_id"
    exit $?
    ;;
  stop)
    shift
    [ "$#" -eq 2 ] || usage
    [ "$1" = "--worker-id" ] || usage
    worker_id=$2
    if local_worker_exists "$worker_id"; then
      exec "$local_helper" stop --worker-id "$worker_id"
    fi
    bridge_request stop --worker-id "$worker_id"
    exit $?
    ;;
  ""|help|-h|--help)
    usage 0
    ;;
  *)
    echo "unknown firebreak worker subcommand: $subcommand" >&2
    exit 1
    ;;
esac
