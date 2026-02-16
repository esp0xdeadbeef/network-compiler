let
  flake = builtins.getFlake (toString ../..);
  evalNode = import "${flake}/dev/debug-lib/40-node.nix";
in
evalNode {
  cfg = {
    routed = {
      coreRoutingNodeName = null;
    };
  };
  nodeName = null;
}
