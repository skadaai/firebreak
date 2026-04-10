#!/usr/bin/env bash
set -eu

proxy_script=@PROXY_SCRIPT@
tmp_root=${TMPDIR:-/tmp}/firebreak/tmp
mkdir -p "$tmp_root"
smoke_dir=$(mktemp -d "$tmp_root/firebreak-cloud-hypervisor-egress.XXXXXX")

unix_socket=$smoke_dir/notify.vsock_3128
upstream_log=$smoke_dir/upstream.log
proxy_log=$smoke_dir/proxy.log

cat >"$smoke_dir/upstream.py" <<'PY'
import http.server
import socketserver


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"egress proxy ok\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


with socketserver.TCPServer(("127.0.0.1", 38128), Handler) as server:
    server.serve_forever()
PY

python3 "$smoke_dir/upstream.py" >"$upstream_log" 2>&1 &
upstream_pid=$!

env \
  FIREBREAK_CH_EGRESS_SOCKET="$unix_socket" \
  FIREBREAK_CH_EGRESS_ALLOW_LOOPBACK=1 \
  python3 "$proxy_script" >"$proxy_log" 2>&1 &
proxy_pid=$!

cleanup_children() {
  kill "$proxy_pid" "$upstream_pid" 2>/dev/null || true
  wait "$proxy_pid" "$upstream_pid" 2>/dev/null || true
}
trap 'cleanup_children; rm -rf "$smoke_dir"' EXIT INT TERM

for _ in $(seq 1 50); do
  if [ -S "$unix_socket" ]; then
    break
  fi
  sleep 0.1
done

for _ in $(seq 1 50); do
  if python3 - <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(0.1)
try:
    sock.connect(("127.0.0.1", 38128))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
raise SystemExit(0)
PY
  then
    break
  fi
  sleep 0.1
done

if ! [ -S "$unix_socket" ]; then
  cat "$proxy_log" >&2 || true
  echo "egress proxy smoke did not create unix socket" >&2
  exit 1
fi

response=$(UNIX_SOCKET="$unix_socket" python3 - <<'PY'
import os
import socket

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(os.environ["UNIX_SOCKET"])
sock.sendall(
    b"GET http://127.0.0.1:38128/ HTTP/1.1\r\n"
    b"Host: 127.0.0.1:38128\r\n"
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
    echo "egress proxy smoke did not return HTTP 200" >&2
    exit 1
    ;;
esac

case "$response" in
  *"egress proxy ok"* ) ;;
  *)
    printf '%s\n' "$response" >&2
    echo "egress proxy smoke did not proxy upstream body" >&2
    exit 1
    ;;
esac

printf '%s\n' "Cloud Hypervisor egress proxy smoke test passed"
