set -eu

runtime_backend=@RUNTIME_BACKEND@

emit_cloud_hypervisor_fs() {
  tag=$1
  socket_path=$2
  [ -n "$socket_path" ] || return 0
  printf '%s\n' "--fs" "tag=${tag},socket=${socket_path}"
}

emit_qemu_virtiofs_share() {
  share_id=$1
  socket_path=$2
  tag=$3
  [ -n "$socket_path" ] || return 0
  printf '%s\n' \
    "-chardev" "socket,id=${share_id},path=${socket_path}" \
    "-device" "vhost-user-fs-pci,chardev=${share_id},tag=${tag}"
}

case "$runtime_backend" in
  qemu)
    [ -n "${MICROVM_HOST_CWD_SOCKET:-}" ] || exit 0
    emit_qemu_virtiofs_share "fs-hostcwd" "${MICROVM_HOST_CWD_SOCKET:-}" "hostcwd"

    if [ -n "${MICROVM_HOST_META_DIR:-}" ]; then
      printf '%s\n' \
        "-fsdev" "local,id=fs-hostmeta,path=${MICROVM_HOST_META_DIR},security_model=none,readonly=true" \
        "-device" "virtio-9p-pci,fsdev=fs-hostmeta,mount_tag=hostmeta"
    fi

    emit_qemu_virtiofs_share "fs-hoststateroot" "${MICROVM_SHARED_STATE_ROOT_SOCKET:-}" "hoststateroot"
    emit_qemu_virtiofs_share "fs-hostcredentialslots" "${MICROVM_SHARED_CREDENTIAL_SLOTS_SOCKET:-}" "hostcredentialslots"
    emit_qemu_virtiofs_share "fs-agentexecoutput" "${MICROVM_AGENT_EXEC_OUTPUT_SOCKET:-}" "hostexecoutput"
    emit_qemu_virtiofs_share "fs-agenttools" "${MICROVM_AGENT_TOOLS_SOCKET:-}" "hostagenttools"
    emit_qemu_virtiofs_share "fs-workerbridge" "${MICROVM_WORKER_BRIDGE_SOCKET:-}" "hostworkerbridge"
    ;;
  cloud-hypervisor)
    emit_cloud_hypervisor_fs "hostcwd" "${MICROVM_HOST_CWD_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostmeta" "${MICROVM_HOST_META_SOCKET:-}"
    emit_cloud_hypervisor_fs "hoststateroot" "${MICROVM_SHARED_STATE_ROOT_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostcredentialslots" "${MICROVM_SHARED_CREDENTIAL_SLOTS_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostexecoutput" "${MICROVM_AGENT_EXEC_OUTPUT_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostagenttools" "${MICROVM_AGENT_TOOLS_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostworkerbridge" "${MICROVM_WORKER_BRIDGE_SOCKET:-}"
    ;;
  *)
    echo "unsupported local runtime backend for runtime-extra-args: $runtime_backend" >&2
    exit 1
    ;;
esac
