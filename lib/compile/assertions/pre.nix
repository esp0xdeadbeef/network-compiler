{
  lib,
  policyNodeName,
  coreNodeName,
}:

topo:

let
  mode = topo.defaultRouteMode or "default";
  okModes = [
    "default"
    "computed"
    "blackhole"
  ];

  nodes = topo.nodes or { };
in
{
  assertions = [
    {
      assertion = lib.elem mode okModes;
      message = "defaultRouteMode must be one of: ${lib.concatStringsSep ", " okModes}. Got: '${mode}'.";
    }
    {
      assertion = nodes ? "${policyNodeName}";
      message = "Topology missing policy node '${policyNodeName}'.";
    }
    {
      assertion = nodes ? "${coreNodeName}";
      message = "Topology missing core node '${coreNodeName}'.";
    }
  ];
}
