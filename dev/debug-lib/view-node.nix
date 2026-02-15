{
  lib,
  ulaPrefix,
  tenantV4Base,
}:
nodeName: topo:
let
  q = import ../../lib/query/view-node.nix { inherit lib; };
in
q nodeName topo
