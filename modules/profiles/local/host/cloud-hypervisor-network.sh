# This file is meant to be sourced, not executed. It provides helpers such as
# cloud_hypervisor_local_port_publish_requested for the local Cloud Hypervisor host path.
# shellcheck disable=SC2148,SC2154

cloud_hypervisor_local_port_publish_requested() {
  LOCAL_PUBLISHED_HOST_PORTS_JSON='@LOCAL_PUBLISHED_HOST_PORTS_JSON@' \
    python3 - <<'PY'
import json
import os
import sys

raw = os.environ["LOCAL_PUBLISHED_HOST_PORTS_JSON"].strip()
if not raw:
    raise SystemExit(1)

try:
    entries = json.loads(raw)
except ValueError:
    raise SystemExit(1)

raise SystemExit(0 if entries else 1)
PY
}

cloud_hypervisor_setup_local_network() {
  [ "$runtime_backend" = "cloud-hypervisor" ] || return 0
  cloud_hypervisor_start_rootless_port_publishers

  if [ "${FIREBREAK_FULL_GUEST_NETWORK:-0}" != "1" ]; then
    return 0
  fi

  host_kernel=$(uname -s 2>/dev/null || printf '%s' unknown)
  case "$host_kernel" in
    Linux) ;;
    *)
      echo "cloud-hypervisor local networking is supported only on Linux hosts" >&2
      exit 1
      ;;
  esac

  cloud_hypervisor_require_privileged_access
  cloud_hypervisor_compute_network_plan
  cloud_hypervisor_write_guest_network_metadata
  cloud_hypervisor_create_tap_interface
  cloud_hypervisor_enable_nat
  export MICROVM_CLOUD_HYPERVISOR_TAP_INTERFACE=$cloud_hypervisor_tap_interface
}

# shellcheck disable=SC2329
cloud_hypervisor_cleanup_local_network() {
  if [ -n "${cloud_hypervisor_proxy_pids:-}" ]; then
    for proxy_pid in $cloud_hypervisor_proxy_pids; do
      kill "$proxy_pid" 2>/dev/null || true
      wait "$proxy_pid" 2>/dev/null || true
    done
  fi

  if [ -n "${cloud_hypervisor_forward_rule_established:-}" ]; then
    cloud_hypervisor_run_privileged "$cloud_hypervisor_iptables_command" -w -D FORWARD \
      -i "$cloud_hypervisor_outbound_interface" \
      -o "$cloud_hypervisor_tap_interface" \
      -m conntrack \
      --ctstate RELATED,ESTABLISHED \
      -j ACCEPT 2>/dev/null || true
  fi

  if [ -n "${cloud_hypervisor_forward_rule_outbound:-}" ]; then
    cloud_hypervisor_run_privileged "$cloud_hypervisor_iptables_command" -w -D FORWARD \
      -i "$cloud_hypervisor_tap_interface" \
      -o "$cloud_hypervisor_outbound_interface" \
      -j ACCEPT 2>/dev/null || true
  fi

  if [ -n "${cloud_hypervisor_masquerade_rule:-}" ]; then
    cloud_hypervisor_run_privileged "$cloud_hypervisor_iptables_command" -w -t nat -D POSTROUTING \
      -s "$cloud_hypervisor_subnet_cidr" \
      -o "$cloud_hypervisor_outbound_interface" \
      -j MASQUERADE 2>/dev/null || true
  fi

  if [ -n "${cloud_hypervisor_tap_interface:-}" ]; then
    cloud_hypervisor_run_privileged "$cloud_hypervisor_ip_command" link delete "$cloud_hypervisor_tap_interface" 2>/dev/null || true
  fi
}

cloud_hypervisor_require_privileged_access() {
  cloud_hypervisor_ip_command=$(command -v ip)
  cloud_hypervisor_iptables_command=$(command -v iptables)

  if [ "$(id -u)" -eq 0 ]; then
    cloud_hypervisor_privileged_prefix=""
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo "cloud-hypervisor local networking requires sudo. See guides/cloud-hypervisor-local-linux.md." >&2
    exit 1
  fi

  if ! sudo -n "$cloud_hypervisor_ip_command" link show >/dev/null 2>&1; then
    echo "cloud-hypervisor local networking requires passwordless sudo for host networking commands. See guides/cloud-hypervisor-local-linux.md." >&2
    exit 1
  fi

  if ! sudo -n "$cloud_hypervisor_iptables_command" -w -L >/dev/null 2>&1; then
    echo "cloud-hypervisor local networking requires passwordless sudo for host firewall commands. See guides/cloud-hypervisor-local-linux.md." >&2
    exit 1
  fi

  cloud_hypervisor_privileged_prefix="sudo -n"
}

cloud_hypervisor_run_privileged() {
  if [ -n "${cloud_hypervisor_privileged_prefix:-}" ]; then
    sudo -n "$@"
  else
    "$@"
  fi
}

cloud_hypervisor_compute_network_plan() {
  network_seed_input=${host_runtime_dir}:${runner_workdir}:${control_socket}
  network_seed_hash=$(printf '%s' "$network_seed_input" | sha256sum)
  network_seed_hash=${network_seed_hash%% *}

  subnet_octet_2=$((64 + (16#${network_seed_hash:0:2} % 64)))
  subnet_octet_3=$((16#${network_seed_hash:2:2}))
  cloud_hypervisor_tap_interface=fbch${network_seed_hash:0:10}
  cloud_hypervisor_subnet_cidr=100.${subnet_octet_2}.${subnet_octet_3}.0/24
  cloud_hypervisor_host_ipv4=100.${subnet_octet_2}.${subnet_octet_3}.1
  cloud_hypervisor_host_ipv4_cidr=${cloud_hypervisor_host_ipv4}/24
  cloud_hypervisor_guest_ipv4=100.${subnet_octet_2}.${subnet_octet_3}.2
  cloud_hypervisor_guest_ipv4_cidr=${cloud_hypervisor_guest_ipv4}/24
  cloud_hypervisor_outbound_interface=$(ip route show default 2>/dev/null | awk '/default/ { print $5; exit }')

  if [ -z "$cloud_hypervisor_outbound_interface" ]; then
    echo "cloud-hypervisor local networking could not resolve a host default network interface" >&2
    exit 1
  fi

  if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || printf '0')" != "1" ]; then
    echo "cloud-hypervisor local networking requires net.ipv4.ip_forward=1. See guides/cloud-hypervisor-local-linux.md." >&2
    exit 1
  fi
}

cloud_hypervisor_write_guest_network_metadata() {
  dns_servers_file=$host_meta_dir/network-dns-servers
  : > "$dns_servers_file"

  if [ -r /run/systemd/resolve/resolv.conf ]; then
    grep '^nameserver ' /run/systemd/resolve/resolv.conf | awk '{ print $2 }' >> "$dns_servers_file" || true
  fi

  if ! [ -s "$dns_servers_file" ] && [ -r /etc/resolv.conf ]; then
    grep '^nameserver ' /etc/resolv.conf | awk '{ print $2 }' | grep -vE '^(127\.|::1$)' >> "$dns_servers_file" || true
  fi

  if ! [ -s "$dns_servers_file" ]; then
    printf '%s\n' "1.1.1.1" "8.8.8.8" > "$dns_servers_file"
  fi

  printf '%s\n' "$cloud_hypervisor_guest_ipv4_cidr" > "$host_meta_dir/network-guest-ipv4-cidr"
  printf '%s\n' "$cloud_hypervisor_host_ipv4" > "$host_meta_dir/network-gateway-ipv4"
  printf '%s\n' "$cloud_hypervisor_host_ipv4" > "$host_meta_dir/network-host-ipv4"
  printf '%s\n' "$cloud_hypervisor_subnet_cidr" > "$host_meta_dir/network-subnet-ipv4-cidr"
  printf '%s\n' "$cloud_hypervisor_tap_interface" > "$host_meta_dir/network-tap-interface"
}

cloud_hypervisor_start_rootless_port_publishers() {
  [ "$runtime_backend" = "cloud-hypervisor" ] || return 0
  cloud_hypervisor_local_port_publish_requested || return 0

  publish_spec_file=$host_runtime_dir/cloud-hypervisor-port-publish.tsv
  : > "$publish_spec_file"

  LOCAL_PUBLISHED_HOST_PORTS_JSON='@LOCAL_PUBLISHED_HOST_PORTS_JSON@' \
    PUBLISH_SPEC_FILE="$publish_spec_file" \
    python3 - <<'PY'
import json
import os

raw = os.environ["LOCAL_PUBLISHED_HOST_PORTS_JSON"]
target = os.environ["PUBLISH_SPEC_FILE"]
try:
    entries = json.loads(raw)
except ValueError as exc:
    raise SystemExit(f"invalid local published host ports json: {exc}")

with open(target, "w", encoding="utf-8") as handle:
    for entry in entries:
        proto = (entry.get("proto") or "tcp").strip().lower()
        if proto != "tcp":
            raise SystemExit(f"unsupported cloud-hypervisor publish protocol: {proto}")
        if (entry.get("from") or "host").strip().lower() != "host":
            raise SystemExit("cloud-hypervisor local publishing supports only host-originated forwards")
        host = entry.get("host") or {}
        guest = entry.get("guest") or {}
        host_address = str(host.get("address") or "127.0.0.1").strip()
        if "port" not in host:
            raise SystemExit(f"missing 'port' in host entry: {entry!r}")
        if "port" not in guest:
            raise SystemExit(f"missing 'port' in guest entry: {entry!r}")
        host_port = int(host["port"])
        guest_port = int(guest["port"])
        handle.write(f"{host_address}\t{host_port}\t{guest_port}\n")
PY

  cloud_hypervisor_proxy_pids=""
  cloud_hypervisor_port_publish_proxy_script=$host_runtime_dir/cloud-hypervisor-port-publish.py
  cat >"$cloud_hypervisor_port_publish_proxy_script" <<'PY'
@FIREBREAK_CLOUD_HYPERVISOR_PORT_PUBLISH_PROXY_PY@
PY
  chmod 0555 "$cloud_hypervisor_port_publish_proxy_script"

  while IFS=$'\t' read -r host_address host_port guest_port; do
    [ -n "$host_address" ] || continue
    env \
      FIREBREAK_CH_PUBLISH_LISTEN_HOST="$host_address" \
      FIREBREAK_CH_PUBLISH_LISTEN_PORT="$host_port" \
      FIREBREAK_CH_PUBLISH_MUX_SOCKET="$runner_launch_dir/notify.vsock" \
      FIREBREAK_CH_PUBLISH_GUEST_PORT="$guest_port" \
      python3 "$cloud_hypervisor_port_publish_proxy_script" >"$host_runtime_dir/port-${host_port}.log" 2>&1 &
    proxy_pid=$!
    sleep 0.2
    if ! kill -0 "$proxy_pid" 2>/dev/null; then
      wait "$proxy_pid" 2>/dev/null || true
      echo "failed to publish host port ${host_address}:${host_port} to guest port ${guest_port}" >&2
      exit 1
    fi
    cloud_hypervisor_proxy_pids="${cloud_hypervisor_proxy_pids:+$cloud_hypervisor_proxy_pids }$proxy_pid"
    trace_wrapper "cloud-hypervisor-port-publish:${host_address}:${host_port}->${guest_port}"
  done < "$publish_spec_file"
}

cloud_hypervisor_create_tap_interface() {
  cloud_hypervisor_run_privileged "$cloud_hypervisor_ip_command" link delete "$cloud_hypervisor_tap_interface" 2>/dev/null || true
  cloud_hypervisor_run_privileged "$cloud_hypervisor_ip_command" tuntap add name "$cloud_hypervisor_tap_interface" mode tap user "$host_uid"
  cloud_hypervisor_run_privileged "$cloud_hypervisor_ip_command" addr add "$cloud_hypervisor_host_ipv4_cidr" dev "$cloud_hypervisor_tap_interface"
  cloud_hypervisor_run_privileged "$cloud_hypervisor_ip_command" link set "$cloud_hypervisor_tap_interface" up
  trace_wrapper "cloud-hypervisor-tap-ready:$cloud_hypervisor_tap_interface"
}

cloud_hypervisor_enable_nat() {
  cloud_hypervisor_run_privileged "$cloud_hypervisor_iptables_command" -w -t nat -A POSTROUTING \
    -s "$cloud_hypervisor_subnet_cidr" \
    -o "$cloud_hypervisor_outbound_interface" \
    -j MASQUERADE
  cloud_hypervisor_masquerade_rule=1

  cloud_hypervisor_run_privileged "$cloud_hypervisor_iptables_command" -w -A FORWARD \
    -i "$cloud_hypervisor_tap_interface" \
    -o "$cloud_hypervisor_outbound_interface" \
    -j ACCEPT
  cloud_hypervisor_forward_rule_outbound=1

  cloud_hypervisor_run_privileged "$cloud_hypervisor_iptables_command" -w -A FORWARD \
    -i "$cloud_hypervisor_outbound_interface" \
    -o "$cloud_hypervisor_tap_interface" \
    -m conntrack \
    --ctstate RELATED,ESTABLISHED \
    -j ACCEPT
  cloud_hypervisor_forward_rule_established=1
  trace_wrapper "cloud-hypervisor-nat-ready:$cloud_hypervisor_outbound_interface"
}
