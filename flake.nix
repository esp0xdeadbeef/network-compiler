{
  description = "nixos-network-compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0182a361324364ae3f436a63005877674cf45efb";
    nixpkgs-network.url = "github:NixOS/nixpkgs/ac56c456ebe4901c561d3ebf1c98fbd970aea753";

    network-labs = {
      url = "github:esp0xdeadbeef/network-labs";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-network
    , network-labs
    ,
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

          layerEntryWarnings =
            { entryBoundary ? "intent-source" }:
            let
              skippedForBoundary = {
                intent-source = [ ];
                compiler-output = [ "intent-source" ];
                forwarding-model-input = [ "intent-source" "network-compiler" ];
                control-plane-input = [ "intent-source" "network-compiler" "network-forwarding-model" ];
                renderer-input = [ "intent-source" "network-compiler" "network-forwarding-model" "network-control-plane-model" ];
                runtime-artifact = [ "intent-source" "network-compiler" "network-forwarding-model" "network-control-plane-model" "renderer" ];
              };
              warningBySkippedLayer = {
                intent-source = "WARN_LAYER_ENTRY_SKIPS_NETWORK_LABS_INTENT_SOURCE";
                network-compiler = "WARN_LAYER_ENTRY_SKIPS_NETWORK_COMPILER";
                network-forwarding-model = "WARN_LAYER_ENTRY_SKIPS_NFM";
                network-control-plane-model = "WARN_LAYER_ENTRY_SKIPS_CPM";
                renderer = "WARN_LAYER_ENTRY_SKIPS_RENDERER";
              };
              skippedUpstreamLayers =
                skippedForBoundary.${entryBoundary} or
                (throw "network-compiler layer-entry warning: unknown entryBoundary '${entryBoundary}'");
            in
            {
              inherit entryBoundary skippedUpstreamLayers;
              warnings = map
                (layer: {
                  code = warningBySkippedLayer.${layer};
                  severity = "warning";
                  skippedLayer = layer;
                  message =
                    if layer == "network-compiler" then
                      "layer-entry starts below network-compiler; compiler execution and validation are not covered by this scenario"
                    else
                      "layer-entry skips ${layer}; that layer is not covered by this scenario";
                })
                skippedUpstreamLayers;
            };

          compileValue = value: compile value;

          compilePath = valueOrPath: compile (readValue valueOrPath);

          writeJSON =
            { value ? null
            , path ? null
            , name ? "output-compiler.json"
            ,
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
          sourceNarHash = self.sourceInfo.narHash or "";
          sourceRevision = self.sourceInfo.rev or "";
          sourceLastModified =
            if sourceRevision != "" then
              toString (self.sourceInfo.lastModified or self.lastModified or 0)
            else
              "unknown";
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
              flake = builtins.getFlake "path:${self.outPath}";
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

            gitRev="unknown"
            gitDirty=true
            repoRoot="$(${pkgs.git}/bin/git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
            repoRemote=""
            if [[ -n "$repoRoot" ]]; then
              repoRemote="$(${pkgs.git}/bin/git -C "$repoRoot" config --get remote.origin.url 2>/dev/null || true)"
            fi
            if [[ -n "$repoRoot" && ( "''${repoRoot##*/}" == "network-compiler" || "$repoRemote" == *"network-compiler"* ) ]]; then
              gitRev="$(${pkgs.git}/bin/git -C "$repoRoot" rev-parse HEAD 2>/dev/null || echo "unknown")"
              if ${pkgs.git}/bin/git -C "$repoRoot" diff --quiet >/dev/null 2>&1 && ${pkgs.git}/bin/git -C "$repoRoot" diff --cached --quiet >/dev/null 2>&1; then
                gitDirty=false
              else
                gitDirty=true
              fi
            fi
            sourceNarHash="${sourceNarHash}"
            sourceLastModified="${sourceLastModified}"
            signedOutput="''${OUTPUT_COMPILER_SIGNED_JSON:-}"
            if [[ -z "$signedOutput" ]]; then
              signedOutput="''${TMPDIR:-/tmp}/network-compiler/output-compiler-signed.json"
            fi
            mkdir -p "$(${pkgs.coreutils}/bin/dirname "$signedOutput")"

            echo "$json" | ${pkgs.jq}/bin/jq -S -c \
              --arg rev "$gitRev" \
              --argjson dirty "$gitDirty" \
              --arg sourceNarHash "$sourceNarHash" \
              --arg sourceLastModified "$sourceLastModified" \
              '.meta.compiler = {
                name: "network-compiler",
                gitRev: $rev,
                gitDirty: $dirty,
                sourceNarHash: $sourceNarHash,
                sourceLastModified: $sourceLastModified
              }' \
              | tee "$signedOutput" \
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
            text = ''
              export NETWORK_COMPILER_ROOT=${self.outPath}
            ''
            + builtins.readFile ./tests/check.sh;
          };

          layerEntryWarningsDrv = pkgs.writeShellApplication {
            name = "layer-entry-warnings";
            runtimeInputs = [
              pkgs.nix
              pkgs.jq
            ];
            text = ''
              set -euo pipefail

              entry_boundary="''${1:-intent-source}"

              expr='
                let
                  flake = builtins.getFlake "path:${self.outPath}";
                in
                  flake.libBySystem.${system}.layerEntryWarnings {
                    entryBoundary = builtins.getEnv "ENTRY_BOUNDARY";
                  }
              '

              json="$(ENTRY_BOUNDARY="$entry_boundary" ${pkgs.nix}/bin/nix eval --impure --json --expr "$expr")"
              printf '%s\n' "$json" \
                | ${pkgs.jq}/bin/jq -r '.warnings[]? | "WARNING: " + .code + ": " + .message' >&2
              printf '%s\n' "$json" | ${pkgs.jq}/bin/jq -S
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

          layer-entry-warnings = {
            type = "app";
            program = "${layerEntryWarningsDrv}/bin/layer-entry-warnings";
          };

          default = {
            type = "app";
            program = "${compileDrv}/bin/app";
          };
        }
      );
    };
}
