#!/usr/bin/env bash
set -eu

proxy_script=@PROXY_SCRIPT@
tmp_root=${TMPDIR:-/tmp}/firebreak/tmp
mkdir -p "$tmp_root"
smoke_dir=$(mktemp -d "$tmp_root/firebreak-cloud-hypervisor-port-publish.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT INT TERM

mux_socket=$smoke_dir/notify.vsock
proxy_log=$smoke_dir/proxy.log
mux_log=$smoke_dir/mux.log
listen_host=127.0.0.1
listen_port=39123
guest_port=48123

cat >"$smoke_dir/mux.py" <<'PY'
import os
import socket
import sys
import threading


socket_path = os.environ["MUX_SOCKET"]
expected_port = os.environ["EXPECTED_PORT"]

try:
    os.unlink(socket_path)
except FileNotFoundError:
    pass


def pump_bidirectional(left, right):
    try:
        while True:
            chunk = left.recv(65536)
            if not chunk:
                return
            right.sendall(chunk)
    finally:
        try:
            right.shutdown(socket.SHUT_WR)
        except OSError:
            pass


listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
listener.bind(socket_path)
listener.listen()

with listener:
    conn, _ = listener.accept()
    with conn:
        prefix = b""
        while not prefix.endswith(b"\n"):
            chunk = conn.recv(1)
            if not chunk:
                raise SystemExit("connection closed before CONNECT preface")
            prefix += chunk
        decoded = prefix.decode("utf-8", "replace")
        if decoded != f"CONNECT {expected_port}\n":
            raise SystemExit(f"unexpected CONNECT preface: {decoded!r}")
        conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 20\r\n\r\nrootless publish ok\n")
PY

env \
  MUX_SOCKET="$mux_socket" \
  EXPECTED_PORT="$guest_port" \
  python3 "$smoke_dir/mux.py" >"$mux_log" 2>&1 &
mux_pid=$!

env \
  FIREBREAK_CH_PUBLISH_LISTEN_HOST="$listen_host" \
  FIREBREAK_CH_PUBLISH_LISTEN_PORT="$listen_port" \
  FIREBREAK_CH_PUBLISH_MUX_SOCKET="$mux_socket" \
  FIREBREAK_CH_PUBLISH_GUEST_PORT="$guest_port" \
  python3 "$proxy_script" >"$proxy_log" 2>&1 &
proxy_pid=$!

cleanup_children() {
  kill "$proxy_pid" "$mux_pid" 2>/dev/null || true
  wait "$proxy_pid" "$mux_pid" 2>/dev/null || true
}
trap 'cleanup_children; rm -rf "$smoke_dir"' EXIT INT TERM

for _ in $(seq 1 50); do
  if [ -S "$mux_socket" ]; then
    break
  fi
  sleep 0.1
done

for _ in $(seq 1 50); do
  if kill -0 "$proxy_pid" 2>/dev/null; then
    break
  fi
  if ! ps -p "$proxy_pid" >/dev/null 2>&1; then
    cat "$proxy_log" >&2 || true
    echo "port publish smoke proxy exited before becoming ready" >&2
    exit 1
  fi
  sleep 0.1
done

response=$(python3 - <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
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
sock.close()
print(b"".join(chunks).decode("utf-8", "replace"))
PY
)

case "$response" in
  *"200 OK"* ) ;;
  *)
    printf '%s\n' "$response" >&2
    cat "$proxy_log" >&2 || true
    cat "$mux_log" >&2 || true
    echo "port publish smoke did not proxy HTTP 200" >&2
    exit 1
    ;;
esac

case "$response" in
  *"rootless publish ok"* ) ;;
  *)
    printf '%s\n' "$response" >&2
    cat "$proxy_log" >&2 || true
    cat "$mux_log" >&2 || true
    echo "port publish smoke did not proxy upstream body" >&2
    exit 1
    ;;
esac

printf '%s\n' "Cloud Hypervisor port publish smoke test passed"
