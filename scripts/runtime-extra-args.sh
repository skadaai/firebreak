set -eu

if [ -z "${MICROVM_HOST_CWD:-}" ]; then
  exit 0
fi

printf '%s\n' \
  -fsdev "local,id=fs-hostcwd,path=$MICROVM_HOST_CWD,security_model=none,readonly=false" \
  -device "virtio-9p-pci,fsdev=fs-hostcwd,mount_tag=hostcwd"

if [ -n "${MICROVM_HOST_META_DIR:-}" ]; then
  printf '%s\n' \
    -fsdev "local,id=fs-hostmeta,path=$MICROVM_HOST_META_DIR,security_model=none,readonly=true" \
    -device "virtio-9p-pci,fsdev=fs-hostmeta,mount_tag=hostmeta"
fi
