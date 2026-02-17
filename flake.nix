{
  description = "Declarative network fabric compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;
    in
    {

      lib.evalNetwork = import ./lib/from-inputs.nix { inherit lib; };

      apps.${system}.debug = {
        type = "app";
        program = toString (
          pkgs.writeShellScript "fabric-debug" ''
            set -euo pipefail
            FILE="$(realpath "$1")"

            nix eval --impure --json --expr "
              let
                flake = builtins.getFlake (toString ./.);
                pkgs  = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
                lib   = pkgs.lib;

                compile = import ./lib/from-inputs.nix { inherit lib; };
                inputs  = import (/. + \"$FILE\");
              in
                compile inputs
            " | jq
          ''
        );

      };

      nixosConfigurations.lab = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./vm.nix ];
      };
    };
}
