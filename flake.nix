# FILE: ./flake.nix
{
  description = "NixOS network topology compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    lib-net = {
      url = "https://gist.github.com/duairc/5c9bb3c922e5d501a1edb9e7b3b845ba/archive/3885f7cd9ed0a746a9d675da6f265d41e9fd6704.tar.gz";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      lib-net,
    }:
    let
      baseLib = nixpkgs.lib;

      extendedLib = baseLib.recursiveUpdate baseLib (
        import ./lib/nix-lib-net/net-extensions.nix {
          lib = baseLib;
          libNet = (import "${lib-net}/net.nix" { lib = baseLib; }).lib.net;
        }
      );
    in
    {
      lib = extendedLib // {
        evalNetwork = import ./lib/eval.nix { lib = extendedLib; };
      };

      nixosModules.default = import ./modules/networkd-from-topology.nix;
    };
}
