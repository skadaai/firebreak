{ lib }:
let
  backendSpecs = {
    qemu = {
      microvmHypervisor = "qemu";
      localHostMetaFsType = "9p";
      roStoreShareProto = "9p";
      capabilities = [
        "interactive-console"
        "local-networking"
        "workspace-share"
        "host-meta-share"
        "shared-state-root"
        "shared-credential-slots"
        "tool-runtimes"
        "worker-bridge"
        "local-port-publish"
      ];
    };

    vfkit = {
      microvmHypervisor = "vfkit";
      localHostMetaFsType = "virtiofs";
      roStoreShareProto = "virtiofs";
      capabilities = [
        "interactive-console"
        "local-networking"
        "workspace-share"
        "host-meta-share"
        "shared-state-root"
        "shared-credential-slots"
        "tool-runtimes"
        "worker-bridge"
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
      "qemu";

  specFor = backendName:
    backendSpecs.${backendName} or (throw "unsupported Firebreak runtime backend: ${backendName}");
}
