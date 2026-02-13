# ./flake.nix
{
  description = "NixOS network topology compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
          in
          f pkgs
        );
    in
    {
      lib =
        let
          baseLib = nixpkgs.lib;
        in
        baseLib
        // {
          net = baseLib.net;
        };

      evalNetwork = import ./lib/eval.nix { };

      nixosModules.default = import ./modules/networkd-from-topology.nix;

      checks = forAllSystems (pkgs: {
        network-lib-tests = pkgs.runCommand "network-lib-tests" { } ''
          export NIX_PATH=nixpkgs=${nixpkgs}
          bash ${nixpkgs}/lib/tests/network.sh
          touch $out
        '';
      });
    };
}
