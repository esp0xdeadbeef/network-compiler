# Overlay model validation helpers, split out of normalize-overlays.nix so the
# normalization module stays under the tracked LOC soft limit.
{ lib }:

siteKey: topo:
let
  nodes = topo.nodes or { };
  nodeNames = builtins.attrNames nodes;

  coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") (
    lib.sort builtins.lessThan nodeNames
  );

  normalizeTerminateOn = raw: if builtins.isList raw then map toString raw else [ (toString raw) ];

  cidrLooksValid =
    family: cidr:
    let
      bits = if family == "ipv4" then 32 else 128;
      parts = lib.splitString "/" cidr;
      base = if builtins.length parts == 2 then builtins.elemAt parts 0 else null;
      lenStr = if builtins.length parts == 2 then builtins.elemAt parts 1 else null;
      lenOk = lenStr != null && builtins.match "[0-9]+" lenStr != null && (lib.toInt lenStr) <= bits;
      v4Ok = base != null && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" base != null;
      v6Ok = base != null && lib.hasInfix ":" base;
    in
    builtins.length parts == 2
    && lenOk
    && (if family == "ipv4" then v4Ok && !(lib.hasInfix ":" base) else v6Ok);

  validateOverlayPrefix =
    idx: family: cidr:
    if cidrLooksValid family cidr then
      cidr
    else
      throw (
        builtins.toJSON {
          code = "E_OVERLAY_PREFIX_INVALID";
          site = siteKey;
          path = [
            "transport"
            "overlays"
            idx
            "prefixes"
            family
          ];
          message = "overlay prefix '${cidr}' is not a valid ${family} CIDR";
          hints = [ "Use a valid ${family} CIDR for the declared family." ];
        }
      );

  resolveTerminateOn =
    idx: ov:
    if ov ? terminateOn then
      normalizeTerminateOn ov.terminateOn
    else if builtins.length coreNodes == 1 then
      [ (builtins.elemAt coreNodes 0) ]
    else
      throw (
        builtins.toJSON {
          code = "E_OVERLAY_AMBIGUOUS_CORE";
          site = siteKey;
          path = [
            "transport"
            "overlays"
            idx
            "terminateOn"
          ];
          message = "overlay.terminateOn required when multiple core nodes exist";
          hints = [ "Set terminateOn to a core node or a list of core nodes." ];
        }
      );

  validateTerm =
    idx: term:
    let
      _termExists = builtins.elem term nodeNames;
      _termIsCore = builtins.elem term coreNodes;
    in
    if !_termExists then
      throw (
        builtins.toJSON {
          code = "E_OVERLAY_UNKNOWN_TERMINATION";
          site = siteKey;
          path = [
            "transport"
            "overlays"
            idx
            "terminateOn"
          ];
          message = "overlay termination node does not exist";
          hints = [ "Set terminateOn to an existing topology.nodes entry." ];
        }
      )
    else if !_termIsCore then
      throw (
        builtins.toJSON {
          code = "E_OVERLAY_TERMINATE_NON_CORE";
          site = siteKey;
          path = [
            "transport"
            "overlays"
            idx
            "terminateOn"
          ];
          message = "overlay must terminate on a core node";
          hints = [ "Set terminateOn to a node with role = \"core\"." ];
        }
      )
    else
      term;
in
{
  inherit coreNodes validateOverlayPrefix resolveTerminateOn validateTerm;
}
