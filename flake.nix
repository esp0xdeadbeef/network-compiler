{
  description = "NixOS network topology compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
    in
    {
      lib = lib // {
        net = lib.net;
        evalNetwork = import ./lib/eval.nix { inherit lib; };
        query = import ./lib/query/default.nix { inherit lib; };
      };

      nixosModules.default = import ./modules/networkd-from-topology.nix;
    };
}
