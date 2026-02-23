{
  description = "nixos-network-compiler";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";

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

            echo "$json" | ${pkgs.jq}/bin/jq -c \
              --arg rev "$gitRev" \
              --argjson dirty "$gitDirty" \
              '. + { meta: { compiler: { gitRev: $rev, gitDirty: $dirty } } }' | tee ./output-signed.json | jq
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
