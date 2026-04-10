import os
import selectors
import socket
import socketserver
import sys


LISTEN_HOST = os.environ.get("FIREBREAK_CH_PUBLISH_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ["FIREBREAK_CH_PUBLISH_LISTEN_PORT"])
MUX_SOCKET = os.environ["FIREBREAK_CH_PUBLISH_MUX_SOCKET"]
GUEST_PORT = int(os.environ["FIREBREAK_CH_PUBLISH_GUEST_PORT"])


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


class PublishHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        mux = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            mux.connect(MUX_SOCKET)
            mux.sendall(f"CONNECT {GUEST_PORT}\n".encode())
        except OSError as exc:
            mux.close()
            raise RuntimeError(
                f"failed to connect Cloud Hypervisor vsock mux {MUX_SOCKET} for guest port {GUEST_PORT}: {exc}"
            ) from exc

        with mux:
            pump_bidirectional(self.request, mux)


def main() -> int:
    with ThreadingTCPServer((LISTEN_HOST, LISTEN_PORT), PublishHandler) as server:
        server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
