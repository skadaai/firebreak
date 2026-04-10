cloud_hypervisor_setup_guest_egress() {
  [ "$runtime_backend" = "cloud-hypervisor" ] || return 0
  cloud_hypervisor_guest_egress_enabled=@GUEST_EGRESS_ENABLED@
  [ "$cloud_hypervisor_guest_egress_enabled" = "1" ] || return 0

  cloud_hypervisor_vsock_path=$runner_launch_dir/notify.vsock
  cloud_hypervisor_guest_egress_socket=${cloud_hypervisor_vsock_path}_@GUEST_EGRESS_PROXY_PORT@
  cloud_hypervisor_guest_egress_script=$host_runtime_dir/cloud-hypervisor-egress-proxy.py
  cloud_hypervisor_guest_egress_log=$host_runtime_dir/cloud-hypervisor-egress.log

  rm -f "$cloud_hypervisor_guest_egress_socket"
  cat >"$cloud_hypervisor_guest_egress_script" <<'PY'
@FIREBREAK_CLOUD_HYPERVISOR_EGRESS_PROXY_PY@
PY
  chmod 0555 "$cloud_hypervisor_guest_egress_script"

  env \
    FIREBREAK_CH_EGRESS_SOCKET="$cloud_hypervisor_guest_egress_socket" \
    FIREBREAK_CH_EGRESS_ALLOW_LOOPBACK="${FIREBREAK_CH_EGRESS_ALLOW_LOOPBACK:-0}" \
    python3 "$cloud_hypervisor_guest_egress_script" >"$cloud_hypervisor_guest_egress_log" 2>&1 &
  cloud_hypervisor_guest_egress_pid=$!

  for _ in $(seq 1 50); do
    if [ -S "$cloud_hypervisor_guest_egress_socket" ]; then
      trace_wrapper "cloud-hypervisor-guest-egress-ready:@GUEST_EGRESS_PROXY_PORT@"
      return 0
    fi
    sleep 0.1
  done

  kill "$cloud_hypervisor_guest_egress_pid" 2>/dev/null || true
  wait "$cloud_hypervisor_guest_egress_pid" 2>/dev/null || true
  echo "cloud-hypervisor guest egress proxy did not create socket: $cloud_hypervisor_guest_egress_socket" >&2
  if [ -s "$cloud_hypervisor_guest_egress_log" ]; then
    cat "$cloud_hypervisor_guest_egress_log" >&2
  fi
  exit 1
}

# shellcheck disable=SC2329
cloud_hypervisor_cleanup_guest_egress() {
  if [ -n "${cloud_hypervisor_guest_egress_pid:-}" ]; then
    kill "$cloud_hypervisor_guest_egress_pid" 2>/dev/null || true
    wait "$cloud_hypervisor_guest_egress_pid" 2>/dev/null || true
  fi

  if [ -n "${cloud_hypervisor_guest_egress_socket:-}" ]; then
    rm -f "$cloud_hypervisor_guest_egress_socket"
  fi
}
