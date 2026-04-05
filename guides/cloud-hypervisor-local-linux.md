# Cloud Hypervisor Local Linux Host Setup

The Linux local Cloud Hypervisor backend is fail-fast. It will not fall back to QEMU-style user networking.

If you select the Cloud Hypervisor backend locally, the host must provide:

- IPv4 forwarding enabled
- passwordless `sudo` for the Firebreak user on that machine

## 1. Enable IPv4 Forwarding

Check the current setting:

```bash
cat /proc/sys/net/ipv4/ip_forward
```

If it prints `0`, enable it now:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

To persist it across reboots on NixOS, add this to your host configuration:

```nix
boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
```

Then rebuild your host system.

## 2. Allow Non-Interactive Root Networking Commands

Firebreak local Cloud Hypervisor networking creates a tap device and installs temporary NAT rules. The runtime calls `sudo -n`, so interactive password prompts are intentionally unsupported.

For this experimental backend, the simplest supported setup is passwordless `sudo` for your user on that development machine.

Create a sudoers drop-in with `visudo`:

```bash
sudo visudo -f /etc/sudoers.d/firebreak-cloud-hypervisor
```

Add:

```text
your-user ALL=(root) NOPASSWD: ALL
```

Replace `your-user` with the Unix account that launches Firebreak.

This is intentionally broad because the local Cloud Hypervisor runtime is still experimental and the exact Nix store command paths are build-specific.

## 3. Validate Host Readiness

Confirm both conditions before testing Firebreak:

```bash
cat /proc/sys/net/ipv4/ip_forward
sudo -n ip link show >/dev/null
sudo -n iptables -w -L >/dev/null
```

The first command must print `1`. The other two commands must exit successfully without prompting.
