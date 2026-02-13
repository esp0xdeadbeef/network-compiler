{ lib }:

{
  tenantVlans,
  policyAccessTransitBase,
  corePolicyTransitVlan,

  policyAccessOffset ? 0,

  policyNodeName ? "s-router-policy-only",
  coreNodeName ? "s-router-core-wan",
  accessNodePrefix ? "s-router-access-",

  domain ? "lan.",
  reservedVlans ? [ 1 ],
  forbiddenVlanRanges ? null,

  ulaPrefix,
  tenantV4Base,
  ...
}@args:

let
  addr = import ./model/addressing.nix { inherit lib; };

  policyNode = policyNodeName;
  coreNode = coreNodeName;

  forbiddenRanges = if forbiddenVlanRanges == null then [ ] else forbiddenVlanRanges;

  _assertForbiddenRanges =
    lib.assertMsg
      (
        builtins.isList forbiddenRanges
        && lib.all (
          r: builtins.isAttrs r && r ? from && r ? to && builtins.isInt r.from && builtins.isInt r.to
        ) forbiddenRanges
      )
      ''
        forbiddenVlanRanges must be a list of attribute sets of the form:
          { from = <int>; to = <int>; }

        To disable, use:
          forbiddenVlanRanges = [ ];
      '';

  accessNodeFor = vid: "${accessNodePrefix}${toString vid}";

  accessTransitVlanFor = vid: policyAccessTransitBase + policyAccessOffset + vid;

  baseIfs = {
    lan = "lan";
  };

  mkAccess = vid: {
    name = accessNodeFor vid;
    value = {
      ifs = baseIfs // {
        "lan${toString vid}" = "lan-${toString vid}";
      };
    };
  };

  nodes = {
    "${coreNode}" = {
      ifs = baseIfs;
    };

    "${policyNode}" = {
      ifs = baseIfs;
    };
  }
  // (lib.listToAttrs (map mkAccess tenantVlans));

  mkTenantLan =
    vid:
    let
      n = accessNodeFor vid;
      lname = "access-tenant-${toString vid}";
    in
    {
      name = lname;
      value = {
        kind = "lan";
        scope = "internal";
        carrier = "lan";
        vlanId = vid;
        name = lname;
        members = [ n ];
        endpoints = {
          "${n}" = {
            tenant = {
              vlanId = vid;
            };
            gateway = true;
          };
        };
      };
    };

  mkPolicyAccess =
    vid:
    let
      access = accessNodeFor vid;
      vlanId = accessTransitVlanFor vid;
      lname = "policy-access-${toString vid}";
      members = [
        policyNode
        access
      ];
    in
    {
      name = lname;
      value = {
        kind = "p2p";
        scope = "internal";
        carrier = "lan";
        vlanId = vlanId;
        name = lname;
        members = members;
        endpoints = {
          "${access}" = {
            tenant = {
              vlanId = vid;
            };
            addr4 = addr.mkP2P4 {
              v4Base = tenantV4Base;
              inherit vlanId members;
              node = access;
            };
            addr6 = addr.mkP2P6 {
              inherit ulaPrefix vlanId members;
              node = access;
            };
          };

          "${policyNode}" = {
            addr4 = addr.mkP2P4 {
              v4Base = tenantV4Base;
              inherit vlanId members;
              node = policyNode;
            };
            addr6 = addr.mkP2P6 {
              inherit ulaPrefix vlanId members;
              node = policyNode;
            };
          };
        };
      };
    };

  mkPolicyCore =
    let
      lname = "policy-core";
      vlanId = corePolicyTransitVlan;
      members = [
        policyNode
        coreNode
      ];
    in
    {
      name = lname;
      value = {
        kind = "p2p";
        scope = "internal";
        carrier = "lan";
        vlanId = vlanId;
        name = lname;
        members = members;
        endpoints = {
          "${policyNode}" = {
            addr4 = addr.mkP2P4 {
              v4Base = tenantV4Base;
              inherit vlanId members;
              node = policyNode;
            };
            addr6 = addr.mkP2P6 {
              inherit ulaPrefix vlanId members;
              node = policyNode;
            };
          };

          "${coreNode}" = {
            addr4 = addr.mkP2P4 {
              v4Base = tenantV4Base;
              inherit vlanId members;
              node = coreNode;
            };
            addr6 = addr.mkP2P6 {
              inherit ulaPrefix vlanId members;
              node = coreNode;
            };
          };
        };
      };
    };

  links =
    (lib.listToAttrs (map mkTenantLan tenantVlans))
    // (lib.listToAttrs (map mkPolicyAccess tenantVlans))
    // {
      policy-core = (mkPolicyCore).value;
    };

  passthrough = builtins.removeAttrs args [
    "tenantVlans"
    "policyAccessTransitBase"
    "corePolicyTransitVlan"
    "policyAccessOffset"
    "policyNodeName"
    "coreNodeName"
    "accessNodePrefix"
    "domain"
    "reservedVlans"
    "forbiddenVlanRanges"
    "ulaPrefix"
    "tenantV4Base"
  ];
in
builtins.seq _assertForbiddenRanges {
  inherit ulaPrefix tenantV4Base;
  inherit domain;
  inherit nodes links;
  reservedVlans = reservedVlans;
  forbiddenVlanRanges = forbiddenRanges;
}
// passthrough
