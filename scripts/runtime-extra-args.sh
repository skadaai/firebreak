set -eu

if [ -z "${MICROVM_HOST_CWD_SOCKET:-}" ]; then
  exit 0
fi

printf '%s\n' \
  -chardev socket,id=fs-hostcwd,path="$MICROVM_HOST_CWD_SOCKET" \
  -device vhost-user-fs-pci,chardev=fs-hostcwd,tag=hostcwd

if [ -n "${MICROVM_HOST_META_DIR:-}" ]; then
  printf '%s\n' \
    -fsdev local,id=fs-hostmeta,path="$MICROVM_HOST_META_DIR",security_model=none,readonly=true \
    -device virtio-9p-pci,fsdev=fs-hostmeta,mount_tag=hostmeta
fi
