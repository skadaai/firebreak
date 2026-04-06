set -eu

guest_ipv4_cidr_file=@HOST_META_MOUNT@/network-guest-ipv4-cidr
gateway_ipv4_file=@HOST_META_MOUNT@/network-gateway-ipv4
dns_servers_file=@HOST_META_MOUNT@/network-dns-servers

if ! [ -r "$guest_ipv4_cidr_file" ]; then
  exit 0
fi

if ! [ -r "$gateway_ipv4_file" ]; then
  exit 0
fi

network_interface=$(ip -o link show | awk -F': ' '$2 != "lo" { print $2; exit }')
if [ -z "$network_interface" ]; then
  echo "runtime network configuration could not resolve a guest network interface" >&2
  exit 1
fi

guest_ipv4_cidr=$(cat "$guest_ipv4_cidr_file")
gateway_ipv4=$(cat "$gateway_ipv4_file")

if [ -z "$guest_ipv4_cidr" ] || [ -z "$gateway_ipv4" ]; then
  echo "runtime network configuration metadata is incomplete" >&2
  exit 1
fi

ip link set "$network_interface" up
ip addr flush dev "$network_interface"
ip addr add "$guest_ipv4_cidr" dev "$network_interface"
ip route replace default via "$gateway_ipv4" dev "$network_interface"

if [ -r "$dns_servers_file" ]; then
  tmp_resolv_conf=/run/firebreak-resolv.conf
  : > "$tmp_resolv_conf"
  while IFS= read -r dns_server; do
    [ -n "$dns_server" ] || continue
    printf 'nameserver %s\n' "$dns_server" >> "$tmp_resolv_conf"
  done < "$dns_servers_file"

  if [ -s "$tmp_resolv_conf" ]; then
    rm -f /etc/resolv.conf
    cp "$tmp_resolv_conf" /etc/resolv.conf
    chmod 0644 /etc/resolv.conf
  fi
fi
