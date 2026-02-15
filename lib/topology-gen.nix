{ lib }:

args@{
  tenantVlans,
  policyAccessTransitBase,
  corePolicyTransitVlan,
  policyAccessOffset ? 0,
  policyNodeName,
  coreNodeName,
  accessNodePrefix,
  domain ? "lan.",
  reservedVlans ? [ 1 ],
  forbiddenVlanRanges ? null,
  ulaPrefix,
  tenantV4Base,
  ...
}:

let
  addr = import ./model/addressing.nix { inherit lib; };

  _ = import ./topology/assertions.nix { inherit lib; } {
    inherit
      policyNodeName
      coreNodeName
      accessNodePrefix
      forbiddenVlanRanges
      ;
  };

  nodes = import ./topology/nodes.nix { inherit lib; } {
    inherit
      tenantVlans
      accessNodePrefix
      policyNodeName
      coreNodeName
      ;
  };

  tenantLinks = import ./topology/links-tenant.nix { inherit lib addr; } {
    inherit
      tenantVlans
      tenantV4Base
      ulaPrefix
      accessNodePrefix
      ;
  };

  policyAccessLinks = import ./topology/links-policy-access.nix { inherit lib addr; } {
    inherit
      tenantVlans
      tenantV4Base
      ulaPrefix
      policyAccessTransitBase
      policyAccessOffset
      accessNodePrefix
      policyNodeName
      ;
  };

  policyCoreLink = import ./topology/links-policy-core.nix { inherit lib addr; } {
    inherit
      corePolicyTransitVlan
      tenantV4Base
      ulaPrefix
      policyNodeName
      coreNodeName
      ;
  };

  passthrough = builtins.removeAttrs args [
    "links"
    "nodes"
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
  inherit nodes;
  links = tenantLinks // policyAccessLinks // policyCoreLink;
  inherit
    ulaPrefix
    tenantV4Base
    domain
    policyNodeName
    coreNodeName
    reservedVlans
    forbiddenVlanRanges
    ;
}
// passthrough
