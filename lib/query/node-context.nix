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

  # Prefer compiled view (all.nodes), then routed.nodes
  nodeSource =
    if allNodes ? "${requestedNode}" then
      allNodes.${requestedNode}
    else if (routed.nodes or { }) ? "${requestedNode}" then
      routed.nodes.${requestedNode}
    else
      throw "node-context: node '${requestedNode}' not found";

  # Detect fabric context nodes like "s-router-core-isp-2"
  isFabricContext =
    lib.hasPrefix "${fabricHost}-" requestedNode
    && (routed.nodes or { }) ? "${requestedNode}";

  enrichedInterfaces =
    if isFabricContext then
      (routed.nodes.${requestedNode}.interfaces or { })
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
      throw "node-context: link '${linkName}' not found on node '${requestedNode}'";

in
sanitize {
  node = requestedNode;
  link = linkName;
  config = selected;
}

