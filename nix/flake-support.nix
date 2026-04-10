{ self, nixpkgs, microvm, system, guestSystem ? system }:
let
  lib = nixpkgs.lib;
  nixpkgsConfig = import ./support/nixpkgs-config.nix {
    inherit lib;
  };
  pkgs = import nixpkgs {
    inherit system;
    config = nixpkgsConfig;
  };

  renderTemplate = vars: path:
    lib.replaceStrings
      (builtins.attrNames vars)
      (builtins.attrValues vars)
      (builtins.readFile path);

  runtimeBackends = import ./support/runtime-backends.nix {
    inherit lib;
  };

  runtime = import ./support/runtime.nix {
    inherit self nixpkgs microvm system guestSystem renderTemplate runtimeBackends nixpkgsConfig;
  };

  projects = import ./support/projects.nix {
    inherit lib pkgs renderTemplate;
    inherit (runtime) mkLocalVmArtifacts;
  };

  packages = import ./support/packages.nix {
    inherit self system pkgs renderTemplate;
    inherit (runtime) mkLocalVmArtifacts;
  };
in
runtime // projects // packages // {
  inherit lib pkgs renderTemplate runtimeBackends;
  hostIsDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  hostIsLinux = pkgs.stdenv.hostPlatform.isLinux;
  hostSystem = system;
  inherit guestSystem;
}
