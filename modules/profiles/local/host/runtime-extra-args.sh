set -eu

runtime_backend=@RUNTIME_BACKEND@

emit_cloud_hypervisor_fs() {
  tag=$1
  socket_path=$2
  [ -n "$socket_path" ] || return 0
  printf '%s\n' "--fs" "tag=${tag},socket=${socket_path}"
}

emit_cloud_hypervisor_net() {
  tap_interface=$1
  mac_address=$2
  [ -n "$tap_interface" ] || return 0
  printf '%s\n' "--net" "tap=${tap_interface},mac=${mac_address}"
}

case "$runtime_backend" in
  cloud-hypervisor)
    emit_cloud_hypervisor_net "${MICROVM_CLOUD_HYPERVISOR_TAP_INTERFACE:-}" "@NETWORK_MAC@"
    emit_cloud_hypervisor_fs "ro-store" "${MICROVM_RO_STORE_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostcwd" "${MICROVM_HOST_CWD_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostruntime" "${MICROVM_HOST_RUNTIME_SOCKET:-}"
    emit_cloud_hypervisor_fs "hoststateroot" "${MICROVM_SHARED_STATE_ROOT_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostcredentialslots" "${MICROVM_SHARED_CREDENTIAL_SLOTS_SOCKET:-}"
    emit_cloud_hypervisor_fs "hostagenttools" "${MICROVM_AGENT_TOOLS_SOCKET:-}"
    ;;
  *)
    echo "unsupported local runtime backend for runtime-extra-args: $runtime_backend" >&2
    exit 1
    ;;
esac
