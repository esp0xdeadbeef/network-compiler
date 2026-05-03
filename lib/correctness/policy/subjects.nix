{ lib }:

let
  util = import ../util.nix { inherit lib; };
  external = import ./external-selector.nix { inherit lib; };
  inherit (util) ensure;
  inherit (external) normalizeExternalSelector;

  normalizeSubject =
    siteKey: idx: path: tenantNames: serviceIndex: overlayNames: uplinkNames: subj:
    let
      _shape = ensure (builtins.isAttrs subj) {
        code = "E_CONTRACT_SUBJECT_SHAPE";
        site = siteKey;
        path = path;
        message = "subject must be an attrset";
        hints = [
          "Use { kind = \"tenant\"; name = \"...\"; }."
          "Or use { kind = \"tenant-set\"; members = [ ... ]; }."
          "Or use { kind = \"service\"; name = \"...\"; }."
          "Or use { kind = \"external\"; name = \"wan\"; }."
          "Or use { kind = \"external\"; uplinks = [ \"isp-a\" \"isp-b\" ]; }."
        ];
      };

      kind = subj.kind or null;

      _kind =
        ensure
          (builtins.elem kind [
            "tenant"
            "tenant-set"
            "external"
            "service"
          ])
          {
            code = "E_CONTRACT_SUBJECT_KIND";
            site = siteKey;
            path = path ++ [ "kind" ];
            message = "subject.kind must be 'tenant', 'tenant-set', 'service', or 'external'";
            hints = [
              "Use kind = \"tenant\"."
              "Or kind = \"tenant-set\"."
              "Or kind = \"service\"."
              "Or kind = \"external\"."
            ];
          };
    in
    if kind == "tenant" then
      let
        name = subj.name or null;

        _name = ensure (name != null && builtins.isString name && name != "") {
          code = "E_CONTRACT_SUBJECT_NAME";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "tenant subject requires a non-empty name";
          hints = [ "Set name = \"<tenant-name>\"." ];
        };

        _exists = ensure (builtins.elem name tenantNames) {
          code = "E_CONTRACT_UNKNOWN_TENANT";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "relation references unknown tenant '${name}'";
          hints = [ "Declare tenant '${name}' under ownership.prefixes." ];
        };
      in
      {
        kind = "tenant";
        inherit name;
      }
    else if kind == "tenant-set" then
      let
        members = subj.members or [ ];

        _membersShape =
          ensure (builtins.isList members && builtins.all builtins.isString members && members != [ ])
            {
              code = "E_CONTRACT_SUBJECT_MEMBERS";
              site = siteKey;
              path = path ++ [ "members" ];
              message = "tenant-set subject requires a non-empty members list";
              hints = [ "Set members = [ \"tenant-a\" \"tenant-b\" ]." ];
            };

        _membersExist = builtins.all (name: builtins.elem name tenantNames) members;

        _exists = ensure _membersExist {
          code = "E_CONTRACT_UNKNOWN_TENANT";
          site = siteKey;
          path = path ++ [ "members" ];
          message = "tenant-set includes unknown tenant";
          hints = [ "Ensure every tenant-set member exists under ownership.prefixes." ];
        };
      in
      {
        kind = "tenant-set";
        members = lib.sort builtins.lessThan members;
      }
    else if kind == "service" then
      let
        name = subj.name or null;

        _name = ensure (name != null && builtins.isString name && name != "") {
          code = "E_CONTRACT_SUBJECT_NAME";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "service subject requires a non-empty name";
          hints = [ "Set name = \"<service-name>\"." ];
        };

        _exists = ensure (builtins.hasAttr name serviceIndex) {
          code = "E_CONTRACT_UNKNOWN_SERVICE";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "relation references unknown service '${name}'";
          hints = [ "Declare service '${name}' under communicationContract.services." ];
        };
      in
      {
        kind = "service";
        inherit name;
      }
    else
      normalizeExternalSelector siteKey path overlayNames uplinkNames subj;
in
{
  inherit normalizeSubject;
}
