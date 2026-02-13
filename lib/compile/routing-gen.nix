{
  lib,
  ulaPrefix,
  tenantV4Base,
  policyNodeName ? "s-router-policy-only",
  coreNodeName ? "s-router-core-wan",
}:

topoResolved:

let
  topo0 = topoResolved // {
    defaultRouteMode =
      if topoResolved ? defaultRouteMode then topoResolved.defaultRouteMode else "default";
  };

  pre = import ./assertions/pre.nix { inherit lib policyNodeName coreNodeName; } topo0;

  _pre = lib.assertMsg (lib.all (a: a.assertion) pre.assertions) (
    lib.concatStringsSep "\n" (map (a: a.message) (lib.filter (a: !a.assertion) pre.assertions))
  );

  step0 = import ./routing/upstreams.nix { inherit lib; } topo0;

  step1 = import ./routing/tenant-lan.nix {
    inherit lib ulaPrefix;
  } step0;

  internet = import ./routing/public-prefixes.nix { inherit lib; } step1;

  topoWithInternet = step1 // {
    _internet = internet;
    defaultRouteMode = topo0.defaultRouteMode;
  };

  step2 = import ./routing/policy-access.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      ;
  } topoWithInternet;

  step3 = import ./routing/policy-core.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      coreNodeName
      ;
  } step2;

  post = import ./assertions/post.nix { inherit lib policyNodeName coreNodeName; } step3;

  _post = lib.assertMsg (lib.all (a: a.assertion) post.assertions) (
    lib.concatStringsSep "\n" (map (a: a.message) (lib.filter (a: !a.assertion) post.assertions))
  );

in

builtins.seq _pre (builtins.seq _post step3)
