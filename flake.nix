{
  description = "Declarative network fabric compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      stages = import ./lib/stages.nix { inherit lib; };

      mkStageApp = stageName: exprBody: {
        type = "app";
        program = toString (
          pkgs.writeShellScript "fabric-${stageName}" ''
            set -euo pipefail
            FILE="$(realpath "$1")"

            nix eval --impure --json --expr '
              let
                flake = builtins.getFlake (toString ./.);
                pkgs  = import flake.inputs.nixpkgs { system = "'"${system}"'"; };
                lib   = pkgs.lib;

                stages = import ./lib/stages.nix { inherit lib; };

                p = builtins.toPath "'"$FILE"'";

                inputs0 =
                  if lib.hasSuffix ".json" (toString p) then
                    builtins.fromJSON (builtins.readFile p)
                  else
                    import p;

                inputs  = if builtins.isFunction inputs0 then inputs0 {} else inputs0;
              in
                '"${exprBody}"'
            ' | jq
          ''
        );
      };

    in
    {

      lib.evalNetwork = import ./lib/from-inputs.nix { inherit lib; };

      apps.${system} = {

        debug = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "fabric-debug" ''
              set -euo pipefail
              FILE="$(realpath "$1")"

              nix eval --impure --json --expr "
                let
                  flake = builtins.getFlake (toString ./.);
                  main  = import ./lib/main.nix { nix = flake.inputs.nixpkgs; };
                in
                  (main.fromFile \"$FILE\").sites
              " | jq
            ''
          );
        };

        flatten = mkStageApp "flatten" "stages.flatten inputs";

        normalize = mkStageApp "normalize" "stages.normalize inputs";

        invPre = mkStageApp "invPre" "stages.\"invariants-pre\" inputs";

        compile = mkStageApp "compile" "stages.compile inputs";

        invPost = mkStageApp "invPost" "stages.\"invariants-post\" inputs";

        check = mkStageApp "check" ''
          let
            sites0 = stages.normalize inputs;
            _pre = stages.checkSites sites0;

            compiled = stages.compile inputs;

            
            _post = stages.checkSites compiled;
          in true
        '';
      };

      nixosConfigurations.lab = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./vm.nix ];
      };
    };
}
