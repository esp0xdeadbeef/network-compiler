let
  flake = builtins.getFlake (toString ../..);
  evalNode = import "${flake}/dev/debug-lib/40-node.nix";
in
evalNode {
  cfg = {
    coreNodeName = 123;
  };
  nodeName = null;
}
