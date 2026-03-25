set -eu

bridge_dir=@WORKER_BRIDGE_MOUNT@
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak worker <subcommand> ...
EOF
  exit "${1:-1}"
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
  spawn|list|show|stop)
    ;;
  ""|help|-h|--help)
    usage 0
    ;;
  *)
    echo "unknown firebreak worker subcommand: $subcommand" >&2
    exit 1
    ;;
esac

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
exit "$bridge_exit_code"
