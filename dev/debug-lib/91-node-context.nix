# ./dev/debug-lib/91-node-context.nix
{
  sopsData ? { },
  nodeName ? null,
  linkName ? null,
}:

let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;

  all = import ./90-all.nix { inherit sopsData; };
  routed = import ./30-routing.nix { inherit sopsData; };

  requestedNode =
    if nodeName != null then
      nodeName
    else if routed ? coreRoutingNodeName && builtins.isString routed.coreRoutingNodeName then
      routed.coreRoutingNodeName
    else
      "s-router-core";

  sanitize =
    x:
    let
      t = builtins.typeOf x;
    in
    if t == "lambda" || t == "primop" then
      "<function>"
    else if builtins.isList x then
      map sanitize x
    else if builtins.isAttrs x then
      lib.mapAttrs (_: v: sanitize v) x
    else if t == "path" then
      toString x
    else
      x;

  # Prefer compiled view (all.nodes), then routed.nodes
  nodeSource =
    if all.nodes ? "${requestedNode}" then
      all.nodes.${requestedNode}
    else if routed.nodes ? "${requestedNode}" then
      routed.nodes.${requestedNode}
    else
      throw "91-node-context: node '${requestedNode}' not found";

  fabricHost = "s-router-core";

  # Detect fabric context nodes like "s-router-core-isp-2"
  isFabricContext =
    lib.hasPrefix "${fabricHost}-" requestedNode
    && routed.nodes ? "${requestedNode}";

  fabricNode =
    if all.nodes ? "${fabricHost}" then
      all.nodes.${fabricHost}
    else
      null;

  enrichedInterfaces =
    if isFabricContext then
      let
        routedIfs = routed.nodes.${requestedNode}.interfaces or { };
      in
      routedIfs
    else if nodeSource ? interfaces then
      nodeSource.interfaces
    else
      { };

  selected =
    if linkName == null then
      enrichedInterfaces
    else if enrichedInterfaces ? "${linkName}" then
      enrichedInterfaces.${linkName}
    else
      throw "91-node-context: link '${linkName}' not found on node '${requestedNode}'";

in
sanitize {
  node = requestedNode;
  link = linkName;
  config = selected;
}

