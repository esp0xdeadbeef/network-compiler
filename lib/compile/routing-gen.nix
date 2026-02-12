{
  lib,
  ulaPrefix,
  tenantV4Base,
  policyNodeName ? "s-router-policy-only",
  coreNodeName ? "s-router-core-wan",
}:

topoResolved:

let
  step0 = import ./routing/upstreams.nix { inherit lib; } topoResolved;

  step1 = import ./routing/tenant-lan.nix {
    inherit lib ulaPrefix;
  } step0;

  step2 = import ./routing/policy-access.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      ;
  } step1;

  step3 = import ./routing/policy-core.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      coreNodeName
      ;
  } step2;

  # Compute "internet space" as: global space minus owned prefixes
  internet = import ./routing/public-prefixes.nix { inherit lib; } step3;

  # Attach it to the topo so later routing stages can consume it
  step4 = step3 // {
    _internet = internet;
  };

  # Now rewrite policy-core defaults using the computed internet space
  step5 = import ./routing/policy-core.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      coreNodeName
      ;
  } step4;

in
step5
