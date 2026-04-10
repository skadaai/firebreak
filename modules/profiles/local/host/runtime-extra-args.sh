set -eu

runtime_backend=@RUNTIME_BACKEND@

emit_cloud_hypervisor_net() {
  tap_interface=$1
  mac_address=$2
  [ -n "$tap_interface" ] || return 0
  printf '%s\n' "--net" "tap=${tap_interface},mac=${mac_address}"
}

case "$runtime_backend" in
  cloud-hypervisor)
    emit_cloud_hypervisor_net "${MICROVM_CLOUD_HYPERVISOR_TAP_INTERFACE:-}" "@NETWORK_MAC@"
    ;;
  *)
    echo "unsupported local runtime backend for runtime-extra-args: $runtime_backend" >&2
    exit 1
    ;;
esac
