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

  hasPolicyIntent =
    builtins.isAttrs (topo.policyIntent or null)
    && builtins.isList ((topo.policyIntent or { }).exitTenants or null)
    && builtins.isList ((topo.policyIntent or { }).upstreamClasses or null)
    && builtins.isList ((topo.policyIntent or { }).advertiseClasses or null);
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
    {
      assertion = hasPolicyIntent;
      message = ''
        Topology missing required explicit policy intent.

        Required:
          policyIntent = {
            exitTenants       = [ <vid> ... ];
            upstreamClasses   = [ "default" "internet" "site:<name>" "overlay:<name>" "none" ... ];
            advertiseClasses  = [ "default" "internet" "site:<name>" "overlay:<name>" "none" ... ];
          };

        Routing authority must be explicit; it must NOT be derived from topology connectivity.
      '';
    }
  ];
}
