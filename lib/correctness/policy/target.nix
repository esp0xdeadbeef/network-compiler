{ lib }:

let
  util = import ../util.nix { inherit lib; };
  subjects = import ./subjects.nix { inherit lib; };
  external = import ./external-selector.nix { inherit lib; };
  inherit (util) ensure;
  inherit (subjects) normalizeSubject;
  inherit (external) normalizeExternalSelector;

  normalizeTarget =
    siteKey: idx: tenantNames: serviceIndex: overlayNames: uplinkNames: target:
    let
      basePath = [
        "communicationContract"
        "relations"
        idx
        "to"
      ];
    in
    if target == "any" then
      "any"
    else
      let
        _shape = ensure (builtins.isAttrs target) {
          code = "E_CONTRACT_TARGET_SHAPE";
          site = siteKey;
          path = basePath;
          message = "relation.to must be \"any\" or an attrset";
          hints = [
            "Use \"any\"."
            "Or use { kind = \"external\"; name = \"wan\"; }."
            "Or use { kind = \"external\"; uplinks = [ \"isp-a\" \"isp-b\" ]; }."
            "Or use { kind = \"public-ipv4\"; ipv4 = \"198.51.100.10\"; }."
            "Or use { kind = \"service\"; name = \"dns\"; }."
            "Or use { kind = \"tenant\"; name = \"mgmt\"; }."
          ];
        };

        kind = target.kind or null;

        _kind =
          ensure
            (builtins.elem kind [
              "tenant"
              "tenant-set"
              "service"
              "external"
              "public-ipv4"
            ])
            {
              code = "E_CONTRACT_TARGET_KIND";
              site = siteKey;
              path = basePath ++ [ "kind" ];
              message = "relation.to.kind must be tenant, tenant-set, service, external, or public-ipv4";
              hints = [ "Set kind to a supported target kind." ];
            };
      in
      builtins.seq _shape (
        builtins.seq _kind (
          if
            builtins.elem kind [
              "tenant"
              "tenant-set"
            ]
          then
            normalizeSubject siteKey idx basePath tenantNames serviceIndex overlayNames uplinkNames target
          else if kind == "service" then
            let
              name = target.name or null;

              _name = ensure (name != null && builtins.isString name && name != "") {
                code = "E_CONTRACT_TARGET_NAME";
                site = siteKey;
                path = basePath ++ [ "name" ];
                message = "service target requires a non-empty name";
                hints = [ "Set name = \"<service-name>\"." ];
              };

              _exists = ensure (builtins.hasAttr name serviceIndex) {
                code = "E_CONTRACT_UNKNOWN_SERVICE";
                site = siteKey;
                path = basePath ++ [ "name" ];
                message = "relation references unknown service '${name}'";
                hints = [ "Declare service '${name}' under communicationContract.services." ];
              };
            in
            builtins.seq _name (
              builtins.seq _exists {
                kind = "service";
                inherit name;
              }
            )
          else if kind == "public-ipv4" then
            let
              ipv4 = target.ipv4 or target.address or null;

              _ipv4 = ensure (ipv4 != null && builtins.isString ipv4 && ipv4 != "") {
                code = "E_CONTRACT_TARGET_PUBLIC_IPV4";
                site = siteKey;
                path = basePath ++ [ "ipv4" ];
                message = "public-ipv4 target requires a non-empty ipv4 address";
                hints = [ "Set ipv4 = \"<public-ipv4-address>\"." ];
              };
            in
            builtins.seq _ipv4 {
              kind = "public-ipv4";
              inherit ipv4;
            }
          else
            normalizeExternalSelector siteKey basePath overlayNames uplinkNames target
        )
      );
in
{
  inherit normalizeTarget;
}
