{ lib }:
let
  allowedUnfreePackageNames = [
    "claude-code"
  ];
in {
  allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) allowedUnfreePackageNames;
}
