# FS-322 / FS-470: contract scope prefix-ownership and advertisement
# normalization, split out of build-model/fabric.nix so the fabric assembly
# module stays under the tracked LOC soft limit.
{
  lib,
  siteKey,
  nodes,
  normalizeUplinksForNode,
}:

let
  util = import ../../../correctness/util.nix { inherit lib; };
  inherit (util) throwError;
in
rec {
  # Prefixes a scope owns through its modeled uplinks.
  ownedPrefixesOf =
    nodeName:
    let
      uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (nodes.${nodeName}.uplinks or null);
    in
    lib.sort builtins.lessThan (
      lib.unique (lib.concatMap (u: (u.ipv4 or [ ]) ++ (u.ipv6 or [ ])) (builtins.attrValues uplinks))
    );

  normalizeOffers =
    nodeName: node:
    let
      raw = node.offers or null;
    in
    if raw == null then
      ownedPrefixesOf nodeName
    else if builtins.isList raw && builtins.all builtins.isString raw then
      raw
    else
      throwError {
        code = "E_CONTRACT_OFFERS";
        site = siteKey;
        path = [
          "topology"
          "nodes"
          nodeName
          "offers"
        ];
        message = "topology.nodes.${nodeName}.offers must be a list of prefix strings (FS-322 Scope Reachability; owning item: FS-322).";
        spec = "FS-322 Scope Reachability; owning item: FS-322";
        hints = [ "Declare offers as a list of CIDR prefix strings." ];
      };

  prepare =
    declared:
    let
      advertisesMod = import ./contract-advertises.nix { inherit lib siteKey; };
      ownershipPrefixes = (declared.ownership or { }).prefixes or [ ];
      ownershipPrefixesOf =
        p:
        lib.filter (x: builtins.isString x && x != "") [
          (p.ipv4 or null)
          (p.ipv6 or null)
        ];
      declaredOwnershipPrefixStrings = lib.unique (
        lib.concatMap ownershipPrefixesOf (builtins.filter builtins.isAttrs ownershipPrefixes)
      );
      declaredTenantPrefixesByName = builtins.listToAttrs (
        map
          (p: {
            name = p.name;
            value = ownershipPrefixesOf p;
          })
          (
            builtins.filter (
              p: builtins.isAttrs p && (p.kind or null) == "tenant" && builtins.isString (p.name or null)
            ) ownershipPrefixes
          )
      );

      declareOwnershipFailure =
        {
          nodeName,
          field,
          prefix,
          owner,
          owningItem,
          extraHint,
        }:
        throwError {
          code = "E_CONTRACT_PREFIX_OWNERSHIP";
          site = siteKey;
          path = [
            "topology"
            "nodes"
            nodeName
            field
          ];
          message = "topology.nodes.${nodeName}.${field} lists prefix '${prefix}', which is owned by scope '${owner}'; a scope may only offer or carry prefixes it owns (owning item: ${owningItem}).";
          spec = "${owningItem}";
          hints = [
            "A scope shall not restate a prefix another scope owns (FS-322); reachability toward it is expressed with 'selects'."
          ]
          ++ (if extraHint == null then [ ] else [ extraHint ]);
        };

      validatePrefixOwnership =
        nodeName: node:
        let
          owned = builtins.attrNames declaredTenantPrefixesByName;
          tenantsOwning =
            prefix: lib.filter (t: builtins.elem prefix declaredTenantPrefixesByName.${t}) owned;

          attachedTenants = map (
            a: if builtins.isAttrs a then (a.name or null) else (if builtins.isString a then a else null)
          ) (node.attachments or [ ]);
          nodeOwnsTenant = tenant: tenant == nodeName || builtins.elem tenant attachedTenants;
          checkOffers =
            prefix:
            let
              owners = tenantsOwning prefix;
            in
            if owners == [ ] then
              true
            else if lib.any nodeOwnsTenant owners then
              true
            else
              declareOwnershipFailure {
                inherit nodeName prefix;
                field = "offers";
                owner = builtins.head owners;
                owningItem = "FS-322 Scope Reachability; owning item: FS-322";
                extraHint = "Declare selects = [ \"${builtins.head owners}\" ]; instead of restating the prefix.";
              };
          uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (node.uplinks or null);
          checkUplink =
            uplinkName: uplink:
            let
              prefixes = (uplink.ipv4 or [ ]) ++ (uplink.ipv6 or [ ]);
              nonDefault = builtins.filter (p: p != "0.0.0.0/0" && p != "::/0") prefixes;
            in
            lib.all (
              prefix:
              let
                owners = tenantsOwning prefix;
              in
              if owners == [ ] then
                true
              else if lib.any nodeOwnsTenant owners then
                true
              else
                declareOwnershipFailure {
                  inherit nodeName prefix;
                  field = "uplinks.${uplinkName}";
                  owner = builtins.head owners;
                  owningItem = "FS-260-HDS-010-SDS-010-SMS-010 Default Site Fabric Chain";
                  extraHint = "A core/access that federates other scopes declares no uplinks; use selects (FS-322).";
                }
            ) nonDefault;
          _offers = lib.all checkOffers (normalizeOffers nodeName node);
          _uplinks = lib.all (u: checkUplink u uplinks.${u}) (builtins.attrNames uplinks);
        in
        _offers && _uplinks;

      normalizeAdvertises =
        advertisesMod.make {
          inherit declaredOwnershipPrefixStrings declaredTenantPrefixesByName;
        };
    in
    {
      inherit
        declaredOwnershipPrefixStrings
        declaredTenantPrefixesByName
        normalizeAdvertises
        validatePrefixOwnership
        ;
    };
}
