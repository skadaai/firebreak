import os
import selectors
import socket
import socketserver
import sys


LISTEN_HOST = os.environ.get("FIREBREAK_GUEST_EGRESS_PROXY_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ["FIREBREAK_GUEST_EGRESS_PROXY_PORT"])
HOST_CID = int(os.environ.get("FIREBREAK_GUEST_EGRESS_HOST_CID", "2"))
HOST_PORT = int(os.environ["FIREBREAK_GUEST_EGRESS_HOST_PORT"])


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
                try:
                    target.sendall(chunk)
                except OSError:
                    return
    finally:
        selector.close()


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True


class RelayHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        if not hasattr(socket, "AF_VSOCK"):
            raise RuntimeError("guest kernel or Python runtime does not expose AF_VSOCK")

        upstream = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        try:
            upstream.connect((HOST_CID, HOST_PORT))
        except OSError as exc:
            upstream.close()
            raise RuntimeError(f"failed to connect guest egress relay to vsock {HOST_CID}:{HOST_PORT}: {exc}") from exc

        with upstream:
            pump_bidirectional(self.request, upstream)


def main() -> int:
    with ThreadingTCPServer((LISTEN_HOST, LISTEN_PORT), RelayHandler) as server:
        server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
