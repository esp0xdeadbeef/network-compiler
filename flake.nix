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

      baseLib = nixpkgs.lib;
    in
    {
      lib = baseLib // {
        net = baseLib.net;
      };

      # FIX: pass required { lib } argument to eval.nix
      evalNetwork = import ./lib/eval.nix { lib = baseLib; };

      nixosModules.default = import ./modules/networkd-from-topology.nix;

      checks = forAllSystems (pkgs: {
        network-lib-tests = pkgs.runCommand "network-lib-tests" { } ''
          export NIX_PATH=nixpkgs=${nixpkgs}
          bash ${nixpkgs}/lib/tests/network.sh
          touch $out
        '';

        nixos-network-compiler-positive = pkgs.runCommand "nixos-network-compiler-positive" { } ''
          ${pkgs.nix}/bin/nix eval --raw --impure --expr '
            let
              flake = builtins.getFlake (toString ./.);
              lib = flake.lib;
            in
              import ./tests/evaluate-positive.nix { inherit lib; }
          ' > /dev/null
          touch $out
        '';

        nixos-network-compiler-negative = pkgs.runCommand "nixos-network-compiler-negative" { } ''
          ${pkgs.nix}/bin/nix eval --raw --impure --expr '
            let
              flake = builtins.getFlake (toString ./.);
              lib = flake.lib;
            in
              import ./tests/evaluate-negative.nix { inherit lib; }
          ' > /dev/null
          touch $out
        '';

        nixos-network-compiler-routing-validation =
          pkgs.runCommand "nixos-network-compiler-routing-validation" { }
            ''
              ${pkgs.nix}/bin/nix eval --raw --impure --expr '
                let
                  flake = builtins.getFlake (toString ./.);
                  lib = flake.lib;
                in
                  import ./tests/routing-validation-test.nix { inherit lib; }
              ' > /dev/null
              touch $out
            '';

        # Restored: routing semantics / convergence invariants (positive)
        nixos-network-compiler-routing-semantics =
          pkgs.runCommand "nixos-network-compiler-routing-semantics" { }
            ''
              ${pkgs.nix}/bin/nix eval --raw --impure --expr '
                let
                  flake = builtins.getFlake (toString ./.);
                  lib = flake.lib;
                in
                  import ./tests/routing-semantics-positive.nix { inherit lib; }
              ' > /dev/null
              touch $out
            '';
      });
    };
}
