import ipaddress
import os
import selectors
import socket
import socketserver
import sys
import threading
from urllib.parse import urlsplit


SOCKET_PATH = os.environ["FIREBREAK_CH_EGRESS_SOCKET"]
ALLOW_LOOPBACK = os.environ.get("FIREBREAK_CH_EGRESS_ALLOW_LOOPBACK", "0") == "1"


def is_blocked_host(host: str) -> bool:
    if ALLOW_LOOPBACK:
        return False

    normalized = host.strip().lower().rstrip(".")
    if normalized in {"localhost", "localhost.localdomain"}:
        return True

    try:
        candidate = ipaddress.ip_address(normalized)
    except ValueError:
        return False

    return candidate.is_loopback or candidate.is_unspecified


def pump_bidirectional(left: socket.socket, right: socket.socket) -> None:
    selector = selectors.DefaultSelector()
    selector.register(left, selectors.EVENT_READ, right)
    selector.register(right, selectors.EVENT_READ, left)

    try:
        while True:
            ready = selector.select()
            if not ready:
                continue
            for key, _events in ready:
                source = key.fileobj
                target = key.data
                try:
                    chunk = source.recv(65536)
                except OSError:
                    chunk = b""
                if not chunk:
                    return
                target.sendall(chunk)
    finally:
        selector.close()


class ThreadingUnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True


class ProxyHandler(socketserver.StreamRequestHandler):
    def _deny(self, status: str, detail: str) -> None:
        self.wfile.write(
            (
                f"HTTP/1.1 {status}\r\n"
                "Connection: close\r\n"
                f"Content-Length: {len(detail.encode('utf-8'))}\r\n"
                "Content-Type: text/plain; charset=utf-8\r\n"
                "\r\n"
                f"{detail}"
            ).encode("utf-8")
        )

    def _read_headers(self):
        headers = []
        while True:
            line = self.rfile.readline(65536)
            if not line:
                return None
            headers.append(line)
            if line in {b"\r\n", b"\n"}:
                return headers

    def _tunnel_connect(self, authority: str) -> None:
        host, sep, port_str = authority.rpartition(":")
        if not sep or not host or not port_str:
          self._deny("400 Bad Request", "CONNECT target must be host:port")
          return
        try:
            port = int(port_str)
        except ValueError:
            self._deny("400 Bad Request", "CONNECT target port must be numeric")
            return

        if is_blocked_host(host):
            self._deny("403 Forbidden", "loopback targets are not allowed")
            return

        try:
            upstream = socket.create_connection((host, port))
        except OSError as exc:
            self._deny("502 Bad Gateway", f"failed to connect to {host}:{port}: {exc}")
            return

        with upstream:
            self.wfile.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
            pump_bidirectional(self.connection, upstream)

    def _proxy_http(self, method: str, target: str, version: str, headers) -> None:
        parsed = urlsplit(target)
        if parsed.scheme not in {"http", ""}:
            self._deny("400 Bad Request", "unsupported proxy scheme")
            return
        if not parsed.hostname:
            self._deny("400 Bad Request", "proxy request must use an absolute http:// URL")
            return
        if is_blocked_host(parsed.hostname):
            self._deny("403 Forbidden", "loopback targets are not allowed")
            return

        port = parsed.port or 80
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"

        try:
            upstream = socket.create_connection((parsed.hostname, port))
        except OSError as exc:
            self._deny("502 Bad Gateway", f"failed to connect to {parsed.hostname}:{port}: {exc}")
            return

        with upstream:
            upstream.sendall(f"{method} {path} {version}\r\n".encode("utf-8"))
            for header_line in headers:
                if header_line.lower().startswith(b"proxy-connection:"):
                    continue
                upstream.sendall(header_line)
            pump_bidirectional(self.connection, upstream)

    def handle(self) -> None:
        request_line = self.rfile.readline(65536)
        if not request_line:
            return
        try:
            method, target, version = request_line.decode("latin-1").strip().split(" ", 2)
        except ValueError:
            self._deny("400 Bad Request", "invalid proxy request line")
            return

        headers = self._read_headers()
        if headers is None:
            return

        if method.upper() == "CONNECT":
            self._tunnel_connect(target)
            return

        self._proxy_http(method, target, version, headers)


def main() -> int:
    socket_dir = os.path.dirname(SOCKET_PATH)
    if socket_dir:
        os.makedirs(socket_dir, exist_ok=True)
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass

    with ThreadingUnixServer(SOCKET_PATH, ProxyHandler) as server:
        server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
