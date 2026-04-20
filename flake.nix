{
  description = "nixos-network-compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0182a361324364ae3f436a63005877674cf45efb";
    nixpkgs-network.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";

    network-labs = {
      url = "git+ssh://git@github.com/esp0xdeadbeef/network-labs.git";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-network,
      network-labs,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      readValue =
        valueOrPath:
        if builtins.isPath valueOrPath then
          readValue (builtins.toString valueOrPath)
        else if builtins.isString valueOrPath then
          if valueOrPath == "" then
            { }
          else if builtins.match ".*\\.json$" valueOrPath != null then
            builtins.fromJSON (builtins.readFile valueOrPath)
          else
            let
              value = import valueOrPath;
            in
            if builtins.isFunction value then value { } else value
        else if builtins.isFunction valueOrPath then
          valueOrPath { }
        else
          valueOrPath;

      mkPkgs =
        system:
        let
          patchedPkgs = import nixpkgs-network { inherit system; };
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

      mkSystemLib =
        system:
        let
          pkgs = mkPkgs system;
          compile = import ./lib/main.nix {
            lib = pkgs.lib;
          };
        in
        rec {
          inherit compile;

          readInput = readValue;

          compileValue = value: compile value;

          compilePath = valueOrPath: compile (readValue valueOrPath);

          writeJSON =
            {
              value ? null,
              path ? null,
              name ? "output-compiler.json",
            }:
            let
              resolvedValue =
                if value != null then
                  value
                else if path != null then
                  readValue path
                else
                  throw "network-compiler: writeJSON requires value or path";
            in
            pkgs.writeText name (builtins.toJSON (compile resolvedValue));
        };

      mkEvalApp =
        system: nixExpr:
        let
          pkgs = mkPkgs system;
          labsPath = network-labs.outPath;
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

            if [[ "$input" == labs:* ]]; then
              subpath="''${input#labs:}"
              inputAbs="${labsPath}/''${subpath}"
            else
              inputAbs="$(${pkgs.coreutils}/bin/realpath "$input")"
            fi

            tmp="$(mktemp)"
            trap 'rm -f "$tmp"' EXIT

            cat > "$tmp" <<EOF
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

              compiled = (flake.lib.compile "${system}") inputs;

            in
            ${nixExpr}
            EOF

            json="$(${pkgs.nix}/bin/nix eval --json --impure -f "$tmp")"

            gitRev="$(${pkgs.git}/bin/git rev-parse HEAD 2>/dev/null || echo "unknown")"
            gitDirty=false
            if ${pkgs.git}/bin/git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
              if ${pkgs.git}/bin/git diff --quiet >/dev/null 2>&1 && ${pkgs.git}/bin/git diff --cached --quiet >/dev/null 2>&1; then
                gitDirty=false
              else
                gitDirty=true
              fi
            fi

            echo "$json" | ${pkgs.jq}/bin/jq -S -c \
              --arg rev "$gitRev" \
              --argjson dirty "$gitDirty" \
              '.meta.compiler = { gitRev: $rev, gitDirty: $dirty }' \
              | tee "''${OUTPUT_COMPILER_SIGNED_JSON:-./output-compiler-signed.json}" \
              | ${pkgs.jq}/bin/jq -S
          '';
        };

    in
    {
      lib = {
        compile = system: (mkSystemLib system).compile;
        compilePath = system: (mkSystemLib system).compilePath;
        writeJSON = system: (mkSystemLib system).writeJSON;
      };

      libBySystem = forAllSystems mkSystemLib;

      apps = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;

          compileDrv = mkEvalApp system "compiled";

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

          default = {
            type = "app";
            program = "${compileDrv}/bin/app";
          };
        }
      );
    };
}
