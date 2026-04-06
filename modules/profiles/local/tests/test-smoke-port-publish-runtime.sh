set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$repo_root/modules/base/host/firebreak-project-config.sh"

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-port-publish-runtime.XXXXXX")
vm_log=$smoke_tmp_dir/vm.log
host_port=39123
timeout_seconds=${FIREBREAK_SMOKE_TIMEOUT:-180}
vm_pid=""

# shellcheck disable=SC2329
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ -n "$vm_pid" ]; then
    kill "$vm_pid" 2>/dev/null || true
    wait "$vm_pid" 2>/dev/null || true
  fi
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    echo "port publish runtime smoke preserved artifacts under: $smoke_tmp_dir" >&2
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

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

(
  cd "$repo_root"
  run_with_clean_firebreak_env \
    FIREBREAK_INSTANCE_EPHEMERAL=1 \
    FIREBREAK_LAUNCH_MODE=shell \
    AGENT_VM_COMMAND='sleep 300' \
    timeout --foreground "$timeout_seconds" \
    @FIXTURE_PACKAGE_BIN@
) >"$vm_log" 2>&1 &
vm_pid=$!

response=""
for _ in $(seq 1 120); do
  if ! kill -0 "$vm_pid" 2>/dev/null; then
    cat "$vm_log" >&2 || true
    echo "port publish runtime smoke VM exited before the published port became reachable" >&2
    exit 1
  fi

  if response=$(python3 - 2>/dev/null <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(0.2)
try:
    sock.connect(("127.0.0.1", 39123))
    sock.sendall(
        b"GET / HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\n"
        b"Connection: close\r\n"
        b"\r\n"
    )
    chunks = []
    while True:
        data = sock.recv(65536)
        if not data:
            break
        chunks.append(data)
finally:
    sock.close()

print(b"".join(chunks).decode("utf-8", "replace"))
PY
  ); then
    case "$response" in
      *"rootless publish ok"*)
        printf '%s\n' "Firebreak rootless port publish runtime smoke passed"
        exit 0
        ;;
    esac
  fi

  sleep 1
done

cat "$vm_log" >&2 || true
if [ -n "$response" ]; then
  printf '%s\n' "$response" >&2
fi
echo "port publish runtime smoke did not observe the expected HTTP response on 127.0.0.1:${host_port}" >&2
exit 1
