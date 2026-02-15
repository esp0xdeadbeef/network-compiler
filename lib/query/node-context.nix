# ./lib/query/node-context.nix
{ lib }:

{
  all ? null,
  routed,
  nodeName ? null,
  linkName ? null,

  # fabric host (bridge host) used for context-node detection
  fabricHost ? "s-router-core",
}:

let
  sanitize = import ./sanitize.nix { inherit lib; };

  requestedNode =
    if nodeName != null then
      nodeName
    else if routed ? coreRoutingNodeName && builtins.isString routed.coreRoutingNodeName then
      routed.coreRoutingNodeName
    else
      fabricHost;

  allNodes = if all != null && all ? nodes then all.nodes else { };

  routedNodes = routed.nodes or { };
  routedLinks = routed.links or { };

  # Prefer compiled view (all.nodes), then routed.nodes
  nodeSource =
    if allNodes ? "${requestedNode}" then
      allNodes.${requestedNode}
    else if routedNodes ? "${requestedNode}" then
      routedNodes.${requestedNode}
    else
      throw "node-context: node '${requestedNode}' not found";

  # Detect fabric context nodes like "s-router-core-isp-2"
  isFabricContext =
    lib.hasPrefix "${fabricHost}-" requestedNode
    && routedNodes ? "${requestedNode}";

  # Base interfaces (what this node directly owns)
  baseInterfaces =
    if isFabricContext then
      (routedNodes.${requestedNode}.interfaces or { })
    else if nodeSource ? interfaces then
      nodeSource.interfaces
    else
      { };

  # Merge in fabric-host p2p links (e.g. policy-core) so context nodes
  # also expose the core’s transit context.
  inheritedP2p =
    if isFabricContext && routedNodes ? "${fabricHost}" then
      let
        fabricIfs = routedNodes.${fabricHost}.interfaces or { };
      in
      lib.filterAttrs (_: iface: (iface.kind or null) == "p2p") fabricIfs
    else
      { };

  enrichedInterfaces = inheritedP2p // baseInterfaces;

  selected =
    if linkName == null then
      enrichedInterfaces
    else if enrichedInterfaces ? "${linkName}" then
      enrichedInterfaces.${linkName}
    else
      throw "node-context: link '${linkName}' not found on node '${requestedNode}'";

in
sanitize {
  node = requestedNode;
  link = linkName;
  config = selected;
}

