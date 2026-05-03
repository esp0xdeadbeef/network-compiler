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
            ])
            {
              code = "E_CONTRACT_TARGET_KIND";
              site = siteKey;
              path = basePath ++ [ "kind" ];
              message = "relation.to.kind must be tenant, tenant-set, service, or external";
              hints = [ "Set kind to a supported target kind." ];
            };
      in
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
        {
          kind = "service";
          inherit name;
        }
      else
        normalizeExternalSelector siteKey basePath overlayNames uplinkNames target;
in
{
  inherit normalizeTarget;
}
