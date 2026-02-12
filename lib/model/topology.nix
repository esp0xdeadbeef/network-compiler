{
  ulaPrefix,
  tenantV4Base,
}:

let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  raw = import ./topology-gen.nix { inherit lib; } {
    tenantVlans = [
      10
      20
      30
      40
      50
      60
      70
      80
    ];
    policyAccessTransitBase = 100;
    corePolicyTransitVlan = 200;

    inherit ulaPrefix tenantV4Base;
  };

  resolved = import ./topology-resolve.nix {
    inherit lib ulaPrefix tenantV4Base;
  } raw;

  routed = import ../compile/routing-gen.nix {
    inherit lib ulaPrefix tenantV4Base;
  } resolved;

in
routed
