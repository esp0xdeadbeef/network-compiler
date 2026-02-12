{
  description = "NixOS network topology compiler";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    lib = nixpkgs.lib;
  in {
    lib = {
      evalNetwork = import ./lib/eval.nix { inherit lib; };
    };

    nixosModules.default = import ./modules/networkd-from-topology.nix;
  };
}

