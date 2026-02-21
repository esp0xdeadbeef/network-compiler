{
  description = "nixos-network-compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      mkPkgs = system: import nixpkgs { inherit system; };

      mkEvalApp =
        system: nixExpr:
        let
          pkgs = mkPkgs system;
        in
        pkgs.writeShellApplication {
          name = "app";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.nix
          ];
          text = ''
                      set -euo pipefail

                      if [ "$
                        echo "usage: $0 <input>" >&2
                        exit 2
                      fi

                      input="$1"
                      inputAbs="$(${pkgs.coreutils}/bin/realpath "$input")"

                      tmp="$(mktemp)"
                      trap 'rm -f "$tmp"' EXIT

                      cat > "$tmp" <<NIX
            let
              flake = builtins.getFlake (toString ${self.outPath});
              lib = flake.inputs.nixpkgs.lib;

              readInputs =
                p:
                if lib.hasSuffix ".json" p then
                  builtins.fromJSON (builtins.readFile p)
                else
                  let v = import p; in
                  if builtins.isFunction v then v { } else v;

              inputs = readInputs "$inputAbs";

              flatten = import (flake.outPath + "/lib/flatten-sites.nix") { inherit lib; };
              normalize = import (flake.outPath + "/lib/normalize/from-user-input.nix") { inherit lib; };

              declared = flatten inputs;

              semantic =
                lib.mapAttrs
                  (_: normalize)
                  declared;

              compiled = flake.lib.compile inputs;

            in
            ${nixExpr}
            NIX

                      exec ${pkgs.nix}/bin/nix eval --json --impure -f "$tmp"
          '';
        };
    in
    {
      lib = {
        compile = import ./lib/main.nix {
          lib = nixpkgs.lib;
        };
      };

      apps = forAllSystems (
        system:
        let
          compileDrv = mkEvalApp system ''
            compiled
          '';

          debugDrv = mkEvalApp system ''
            {
              raw = inputs;
              declared = declared;
              semantic = semantic;
              compiled = compiled;
            }
          '';
        in
        {
          compile = {
            type = "app";
            program = "${compileDrv}/bin/app";
          };
          debug = {
            type = "app";
            program = "${debugDrv}/bin/app";
          };
          default = {
            type = "app";
            program = "${compileDrv}/bin/app";
          };
        }
      );
    };
}
