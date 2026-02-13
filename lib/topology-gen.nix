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
  forbiddenVlanRanges ? [
    {
      from = 2;
      to = 9;
    }
  ],

  ulaPrefix,
  tenantV4Base,
  ...
}@args:

let
  addr = import ./model/addressing.nix { inherit lib; };

  policyNode = policyNodeName;
  coreNode = coreNodeName;

  accessNodeFor = vid: "${accessNodePrefix}${toString vid}";

  accessTransitVlanFor = vid: policyAccessTransitBase + policyAccessOffset + vid;

  mkAccess = vid: {
    name = accessNodeFor vid;
    value = {
      ifs = {
        lan = "lan0";
      };
    };
  };

  nodes = {
    "${coreNode}" = {
      ifs = {
        lan = "lan0";
        wan = "wan0";
      };
    };

    "${policyNode}" = {
      ifs = {
        lan = "lan0";
      };
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
{
  inherit ulaPrefix tenantV4Base;
  inherit domain;
  inherit nodes links;
  inherit reservedVlans forbiddenVlanRanges;
}
// passthrough
