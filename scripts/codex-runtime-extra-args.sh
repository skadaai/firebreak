if [ -n "${MICROVM_CODEX_CONFIG_HOST_DIR:-}" ]; then
  printf '%s\n' \
    -chardev socket,id=fs-hostcodexconfig,path="$MICROVM_CODEX_CONFIG_HOST_SOCKET" \
    -device vhost-user-fs-pci,chardev=fs-hostcodexconfig,tag=hostcodexconfig
fi
