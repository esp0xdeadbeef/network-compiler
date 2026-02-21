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

      mkLib =
        system:
        let
          pkgs = mkPkgs system;
        in
        import ./lib { lib = pkgs.lib; };

      mkEvalApp =
        system: expr:
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

            exec ${pkgs.nix}/bin/nix eval \
              --json \
              --impure \
              --expr '
                let
                  flake = builtins.getFlake "'"${self.outPath}"'";

                  inputPath = "'"$inputAbs"'";

                  readInputs =
                    p:
                    if flake.inputs.nixpkgs.lib.hasSuffix ".json" p then
                      builtins.fromJSON (builtins.readFile p)
                    else
                      let v = import p; in
                      if builtins.isFunction v then v { } else v;

                  inputs = readInputs inputPath;
                in
                  '"${expr}"'
              '
          '';
        };
    in
    {
      lib = mkLib "x86_64-linux";

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.writeText "nixos-network-compiler" "nixos-network-compiler";
        }
      );

      apps = forAllSystems (
        system:
        let
          flattenDrv = mkEvalApp system ''
            flake.lib.stages.flatten inputs
          '';

          normalizeDrv = mkEvalApp system ''
            flake.lib.stages.normalize inputs
          '';

          invPreDrv = mkEvalApp system ''
            flake.lib.stages."invariants-pre" inputs
          '';

          compileDrv = mkEvalApp system ''
            let
              sites = flake.lib.stages.compile inputs;
              p2p = flake.lib.stages.p2p inputs;
              siteGraph = flake.lib.stages.siteGraph inputs;
            in
            {
              inherit sites p2p siteGraph;
            }
          '';

          invPostDrv = mkEvalApp system ''
            flake.lib.stages."invariants-post" inputs
          '';

          checkDrv = mkEvalApp system ''
            let
              sites = flake.lib.stages.compile inputs;
            in
              flake.lib.stages.checkSites sites
          '';

          debugDrv = compileDrv;
        in
        {
          flatten = {
            type = "app";
            program = "${flattenDrv}/bin/app";
          };

          normalize = {
            type = "app";
            program = "${normalizeDrv}/bin/app";
          };

          invPre = {
            type = "app";
            program = "${invPreDrv}/bin/app";
          };

          compile = {
            type = "app";
            program = "${compileDrv}/bin/app";
          };

          invPost = {
            type = "app";
            program = "${invPostDrv}/bin/app";
          };

          check = {
            type = "app";
            program = "${checkDrv}/bin/app";
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
