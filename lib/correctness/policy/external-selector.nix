{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) ensure throwError;

  normalizeExternalSelector =
    siteKey: path: overlayNames: scopeNames: ext:
    let
      hasName = ext ? name;
      hasScope = ext ? scope;
      hasUplinks = ext ? uplinks;

      _rejectLegacyUplinks = ensure (!hasUplinks) {
        code = "E_SUPERSEDED_CONTRACT";
        site = siteKey;
        path = path ++ [ "uplinks" ];
        message = "external selector names uplinks; reachability is a scope property, not a permission-relation field";
        spec = "FS-081 Superseded-Contract Rejection; owning item: FS-322 Scope Reachability";
        hints = [
          "FS-081 Superseded-Contract Rejection; owning item: FS-322 Scope Reachability."
          "Remove 'uplinks'; declare 'offers'/'selects' on the scopes and name the exit scope with 'scope = \"<exit-scope>\"' if the relation must pin an exit."
        ];
      };

      _atMostOne =
        ensure
          (
            builtins.length (
              builtins.filter (x: x) [
                hasName
                hasScope
              ]
            ) <= 1
          )
          {
            code = "E_CONTRACT_EXTERNAL_SELECTOR";
            site = siteKey;
            path = path;
            message = "external selector must use at most one of name or scope";
            hints = [
              "Use name = \"east-west\" for an overlay, or scope = \"<exit-scope>\" for an exit scope."
            ];
          };

      _someSelector = ensure (hasName || hasScope || (ext.kind or null) == "external") {
        code = "E_CONTRACT_EXTERNAL_SELECTOR";
        site = siteKey;
        path = path;
        message = "external selector is empty";
        hints = [ "Use { kind = \"external\"; } or { kind = \"external\"; scope = \"<exit-scope>\"; }." ];
      };
    in
    builtins.seq _rejectLegacyUplinks (
      builtins.seq _atMostOne (
        builtins.seq _someSelector (
          if hasScope then
            let
              scope = ext.scope;

              _shape = ensure (builtins.isString scope && scope != "") {
                code = "E_CONTRACT_EXTERNAL_SCOPE";
                site = siteKey;
                path = path ++ [ "scope" ];
                message = "external.scope must be a non-empty scope name";
                hints = [ "Name a modeled exit scope, for example scope = \"onyx\"." ];
              };

              _exists = ensure (builtins.elem scope scopeNames) {
                code = "E_CONTRACT_UNKNOWN_EXTERNAL_SCOPE";
                site = siteKey;
                path = path ++ [ "scope" ];
                message = "relation references exit scope '${scope}', which is not a modeled scope";
                hints = [
                  "Declare the scope under topology.nodes.<scope>, or use a bare { kind = \"external\"; }."
                ];
              };
            in
            {
              kind = "external";
              inherit scope;
            }
          else if hasName then
            let
              name = ext.name;

              _name = ensure (builtins.isString name && name != "") {
                code = "E_CONTRACT_SUBJECT_NAME";
                site = siteKey;
                path = path ++ [ "name" ];
                message = "external selector name must be a non-empty string";
                hints = [ "Use name = \"east-west\" for an overlay." ];
              };
            in
            if builtins.elem name overlayNames then
              {
                kind = "external";
                inherit name;
              }
            else
              throwError {
                code = "E_CONTRACT_UNKNOWN_EXTERNAL";
                site = siteKey;
                path = path ++ [ "name" ];
                message = "relation references unknown overlay '${name}'";
                hints = [
                  "Declare the overlay under transport.overlays[].name."
                  "For an exit scope use { kind = \"external\"; scope = \"${name}\"; }."
                ];
              }
          else
            { kind = "external"; }
        )
      )
    );
in
{
  inherit normalizeExternalSelector;
}
