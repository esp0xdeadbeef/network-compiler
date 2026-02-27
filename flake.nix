{
  description = "nixos-network-compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixpkgs-network.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-network,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      mkPkgs =
        system:
        let
          patchedPkgs = import nixpkgs-network {
            inherit system;
          };

          patchedNetwork = patchedPkgs.lib.network;
        in
        import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              lib = prev.lib // {
                network = patchedNetwork;
              };
            })
          ];
        };

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
            pkgs.git
            pkgs.jq
          ];
          text = ''
            set -euo pipefail

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

              compiled = flake.lib.compile inputs;

            in
            ${nixExpr}
            NIX

            json="$(${pkgs.nix}/bin/nix eval --json --impure -f "$tmp")"

            gitRev="$(${pkgs.git}/bin/git rev-parse HEAD)"
            if ${pkgs.git}/bin/git diff --quiet && ${pkgs.git}/bin/git diff --cached --quiet; then
              gitDirty=false
            else
              gitDirty=true
            fi

            echo "$json" | ${pkgs.jq}/bin/jq -S -c \
              --arg rev "$gitRev" \
              --argjson dirty "$gitDirty" \
              '.meta.compiler = { gitRev: $rev, gitDirty: $dirty }' \
              | tee ./output-signed.json \
              | ${pkgs.jq}/bin/jq -S
          '';
        };
    in
    {
      lib = {
        compile = import ./lib/main.nix {
          lib = (mkPkgs builtins.currentSystem).lib;
        };
      };

      apps = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;

          compileDrv = mkEvalApp system ''
            compiled
          '';

          debugDrv = mkEvalApp system ''
            {
              raw = inputs;
              compiled = compiled;
            }
          '';

          checkDrv = pkgs.writeShellApplication {
            name = "check";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.nix
              pkgs.jq
              pkgs.gnugrep
            ];
            text = builtins.readFile ./tests/check.sh;
          };

          compileAllDrv = pkgs.writeShellApplication {
            name = "compile-all-examples";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.nix
              pkgs.jq
              pkgs.findutils
            ];
            text = ''
              set -euo pipefail

              find examples -type f -name 'inputs.nix' -print0 | while IFS= read -r -d ''\0 f; do
                echo ""
                echo "=== $f ==="
                ${pkgs.nix}/bin/nix run path:.
              done
            '';
          };
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

          check = {
            type = "app";
            program = "${checkDrv}/bin/check";
          };

          compile-all-examples = {
            type = "app";
            program = "${compileAllDrv}/bin/compile-all-examples";
          };

          default = {
            type = "app";
            program = "${compileDrv}/bin/app";
          };
        }
      );
    };
}
