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

if [ -n "${MICROVM_SHARED_AGENT_CONFIG_DIR:-}" ]; then
  printf '%s\n' \
    -chardev socket,id=fs-hostagentconfigroot,path="$MICROVM_SHARED_AGENT_CONFIG_SOCKET" \
    -device vhost-user-fs-pci,chardev=fs-hostagentconfigroot,tag=hostagentconfigroot
fi

if [ -n "${MICROVM_AGENT_EXEC_OUTPUT_SOCKET:-}" ]; then
  printf '%s\n' \
    -chardev socket,id=fs-agentexecoutput,path="$MICROVM_AGENT_EXEC_OUTPUT_SOCKET" \
    -device vhost-user-fs-pci,chardev=fs-agentexecoutput,tag=hostexecoutput
fi

if [ -n "${MICROVM_AGENT_TOOLS_SOCKET:-}" ]; then
  printf '%s\n' \
    -chardev socket,id=fs-agenttools,path="$MICROVM_AGENT_TOOLS_SOCKET" \
    -device vhost-user-fs-pci,chardev=fs-agenttools,tag=hostagenttools
fi

if [ -n "${MICROVM_WORKER_BRIDGE_SOCKET:-}" ]; then
  printf '%s\n' \
    -chardev socket,id=fs-workerbridge,path="$MICROVM_WORKER_BRIDGE_SOCKET" \
    -device vhost-user-fs-pci,chardev=fs-workerbridge,tag=hostworkerbridge
fi
