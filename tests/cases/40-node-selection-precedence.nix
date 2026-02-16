{ lib }:

let
  flake = builtins.getFlake (toString ../..);
  evalNode = import "${flake}/dev/debug-lib/40-node.nix";

  get = cfg: nodeName: evalNode { inherit cfg nodeName; };

  cfgBoth = {
    coreNodeName = "cfg-core";
    routed = {
      coreRoutingNodeName = "routed-core";
    };
  };

  v1 = get cfgBoth "explicit-node";
  v2 = get cfgBoth null;

  v3 = get {
    coreNodeName = "cfg-core";
    routed = { };
  } null;

  _a1 = lib.assertMsg (v1 == "explicit-node") "nodeName precedence broken";
  _a2 = lib.assertMsg (v2 == "routed-core") "routed precedence broken";
  _a3 = lib.assertMsg (v3 == "cfg-core") "cfg fallback broken";
in
builtins.seq _a1 (builtins.seq _a2 (builtins.seq _a3 "OK"))
