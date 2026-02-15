{
  lib,
  ulaPrefix,
  tenantV4Base,

  policyNodeName,
  coreNodeName,

  coreRoutingNodeName ? null,
}:

topoResolved:

let
  topo0 = topoResolved // {
    defaultRouteMode =
      if topoResolved ? defaultRouteMode then topoResolved.defaultRouteMode else "default";
  };

  nodes = topo0.nodes or { };
  links = topo0.links or { };

  policyCoreLink = links."policy-core" or null;

  hasPolicyCoreEndpoint = n: policyCoreLink != null && ((policyCoreLink.endpoints or { }) ? "${n}");

  candidates = lib.filter (n: lib.hasPrefix "${coreNodeName}-" n) (builtins.attrNames nodes);

  sortedCandidates = lib.sort (a: b: a < b) candidates;

  pickFromCandidates =
    if policyCoreLink == null then
      null
    else
      let
        eligible = lib.filter hasPolicyCoreEndpoint sortedCandidates;
      in
      if eligible == [ ] then null else lib.head eligible;

  derivedCoreRouting =
    if coreRoutingNodeName != null then
      if !(nodes ? "${coreRoutingNodeName}") then
        throw ''
          routing-gen: coreRoutingNodeName "${coreRoutingNodeName}" does not exist in topology nodes.
        ''
      else if policyCoreLink != null && !hasPolicyCoreEndpoint coreRoutingNodeName then
        throw ''
          routing-gen: coreRoutingNodeName "${coreRoutingNodeName}" is not an endpoint of link "policy-core".

          Add an endpoint for "${coreRoutingNodeName}" on "policy-core", or unset coreRoutingNodeName.
        ''
      else
        coreRoutingNodeName
    else if nodes ? "${coreNodeName}-wan" && hasPolicyCoreEndpoint "${coreNodeName}-wan" then
      "${coreNodeName}-wan"
    else if pickFromCandidates != null then
      pickFromCandidates
    else if
      nodes ? "${coreNodeName}" && (policyCoreLink == null || hasPolicyCoreEndpoint coreNodeName)
    then
      coreNodeName
    else if sortedCandidates != [ ] then
      lib.head sortedCandidates
    else if nodes ? "${coreNodeName}" then
      coreNodeName
    else
      throw ''
        routing-gen: cannot pick a core routing node.

        coreNodeName (fabric host) = "${coreNodeName}"

        Expected one of:
          - set coreRoutingNodeName explicitly
          - define node "${coreNodeName}-wan"
          - define at least one node matching "${coreNodeName}-*"
          - or ensure node "${coreNodeName}" exists
      '';

  pre = import ./assertions/pre.nix {
    inherit lib policyNodeName;
    coreNodeName = derivedCoreRouting;
  } topo0;

  _pre = lib.assertMsg (lib.all (a: a.assertion) pre.assertions) (
    lib.concatStringsSep "\n" (map (a: a.message) (lib.filter (a: !a.assertion) pre.assertions))
  );

  step0 = import ./routing/upstreams.nix { inherit lib; } topo0;

  step0b = import ./routing/wan-runtime.nix { inherit lib; } step0;

  step1 = import ./routing/tenant-lan.nix {
    inherit lib ulaPrefix;
  } step0b;

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
      ;
    coreNodeName = derivedCoreRouting;
  } step2;

  post = import ./assertions/post.nix {
    inherit lib policyNodeName;
    coreNodeName = derivedCoreRouting;
  } step3;

  _post = lib.assertMsg (lib.all (a: a.assertion) post.assertions) (
    lib.concatStringsSep "\n" (map (a: a.message) (lib.filter (a: !a.assertion) post.assertions))
  );

  materialized = import ../topology-resolve.nix {
    inherit lib ulaPrefix tenantV4Base;
  } step3;

  out = materialized // {
    coreRoutingNodeName = derivedCoreRouting;
  };

in
builtins.seq _pre (builtins.seq _post out)
