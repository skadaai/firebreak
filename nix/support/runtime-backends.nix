{ lib }:
let
  backendSpecs = {
    qemu = {
      microvmHypervisor = "qemu";
      localHostMetaFsType = "virtiofs";
      roStoreShareProto = "9p";
      capabilities = [
        "interactive-console"
        "guest-egress"
        "workspace-share"
        "host-meta-share"
        "shared-state-root"
        "shared-credential-slots"
        "tool-runtimes"
        "worker-bridge"
        "host-port-publish-tcp"
      ];
    };

    vfkit = {
      microvmHypervisor = "vfkit";
      localHostMetaFsType = "virtiofs";
      roStoreShareProto = "virtiofs";
      capabilities = [
        "interactive-console"
        "guest-egress"
        "workspace-share"
        "host-meta-share"
        "shared-state-root"
        "shared-credential-slots"
        "tool-runtimes"
        "worker-bridge"
        "host-port-publish-tcp"
      ];
    };

    cloud-hypervisor = {
      microvmHypervisor = "cloud-hypervisor";
      localHostMetaFsType = "virtiofs";
      roStoreShareProto = "virtiofs";
      capabilities = [
        "interactive-console"
        "workspace-share"
        "host-meta-share"
        "shared-state-root"
        "shared-credential-slots"
        "tool-runtimes"
        "worker-bridge"
        "host-port-publish-tcp"
        "full-guest-network"
        "snapshot"
        "vsock"
      ];
    };

    firecracker = {
      microvmHypervisor = "firecracker";
      localHostMetaFsType = "virtiofs";
      roStoreShareProto = "virtiofs";
      capabilities = [
        "interactive-console"
        "snapshot"
        "vsock"
      ];
    };
  };

  supportedBackendNames = builtins.attrNames backendSpecs;
in {
  inherit supportedBackendNames;

  defaultLocalBackendForHost = hostSystem:
    if lib.hasSuffix "-darwin" hostSystem then
      "vfkit"
    else
      "cloud-hypervisor";

  specFor = backendName:
    backendSpecs.${backendName} or (throw "unsupported Firebreak runtime backend: ${backendName}");
}
