import os
import selectors
import socket
import sys
import threading
import time


LISTEN_HOST = os.environ.get("FIREBREAK_GUEST_PORT_PUBLISH_TARGET_HOST", "127.0.0.1")
LISTEN_PORTS = [
    int(candidate)
    for candidate in os.environ.get("FIREBREAK_GUEST_PORT_PUBLISH_PORTS", "").split(",")
    if candidate.strip()
]


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


def serve_guest_port(guest_port: int) -> None:
    if not hasattr(socket, "AF_VSOCK"):
        raise RuntimeError("guest kernel or Python runtime does not expose AF_VSOCK")

    bind_cid = getattr(socket, "VMADDR_CID_ANY", -1)
    listen_socket = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    listen_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listen_socket.bind((bind_cid, guest_port))
    listen_socket.listen()

    with listen_socket:
        while True:
            client, _address = listen_socket.accept()
            threading.Thread(
                target=handle_connection,
                args=(client, guest_port),
                daemon=True,
            ).start()


def handle_connection(client: socket.socket, guest_port: int) -> None:
    upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        upstream.connect((LISTEN_HOST, guest_port))
    except OSError as exc:
        client.close()
        upstream.close()
        raise RuntimeError(
            f"failed to connect guest port publish relay to {LISTEN_HOST}:{guest_port}: {exc}"
        ) from exc

    with client, upstream:
        pump_bidirectional(client, upstream)


def main() -> int:
    if not LISTEN_PORTS:
        return 0

    for guest_port in LISTEN_PORTS:
        threading.Thread(target=serve_guest_port, args=(guest_port,), daemon=True).start()

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    sys.exit(main())
