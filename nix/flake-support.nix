{ self, nixpkgs, microvm, system, guestSystem ? system }:
let
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};

  renderTemplate = vars: path:
    lib.replaceStrings
      (builtins.attrNames vars)
      (builtins.attrValues vars)
      (builtins.readFile path);

  runtime = import ./support/runtime.nix {
    inherit self nixpkgs microvm system guestSystem renderTemplate;
  };

  projects = import ./support/projects.nix {
    inherit lib pkgs renderTemplate;
    inherit (runtime) mkLocalVmArtifacts;
  };

  packages = import ./support/packages.nix {
    inherit self system pkgs renderTemplate;
  };
in
runtime // projects // packages // {
  inherit lib pkgs renderTemplate;
  hostIsDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  hostIsLinux = pkgs.stdenv.hostPlatform.isLinux;
  hostSystem = system;
  inherit guestSystem;
}
