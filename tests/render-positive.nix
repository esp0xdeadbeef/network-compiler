{ lib }:

let
  eval = import ../lib/eval.nix { inherit lib; };

  topo = import ../lib/topology-gen.nix { inherit lib; } {
    tenantVlans = [ 10 ];
    policyAccessTransitBase = 100;
    corePolicyTransitVlan = 200;
    ulaPrefix = "fd42:dead:beef";
    tenantV4Base = "10.10";
  };

  compiled = eval { topology = topo; };

  renderer = import ../lib/render/networkd/default.nix { inherit lib; };

  rendered = renderer.render {
    all = {
      topology = compiled;
      nodes = compiled.nodes;
    };
    nodeName = "s-router-access-10";
  };

in
builtins.deepSeq rendered "RENDER OK"
