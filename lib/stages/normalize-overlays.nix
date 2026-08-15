{ lib }:

siteKey: topo: declared:

let
  nodes = topo.nodes or { };
  nodeNames = builtins.attrNames nodes;

  coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") (
    lib.sort builtins.lessThan nodeNames
  );

  transport0 = declared.transport or { };
  overlays0 = transport0.overlays or [ ];

  normalizeTerminateOn = raw: if builtins.isList raw then map toString raw else [ (toString raw) ];

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

  normalizeOne =
    idx: ov:
    let
      terms = resolveTerminateOn idx ov;
      validated = map (validateTerm idx) terms;
      rawPeerSite = ov.peerSite or ov.peer or ov.toSite or null;
      peerSites =
        if builtins.isList (ov.peerSites or null) then
          map toString ov.peerSites
        else if builtins.isList (ov.peers or null) then
          map toString ov.peers
        else if rawPeerSite != null then
          [ (toString rawPeerSite) ]
        else
          [ ];
      normalized = {
        name = ov.name or "overlay-${toString idx}";
        peerSite = if peerSites == [ ] then null else builtins.head peerSites;
        peerSites = peerSites;
        terminateOn = validated;
        mustTraverse = ov.mustTraverse or [ ];
        underlayTrafficTypes = ov.underlayTrafficTypes or [ ];
      }
      // lib.optionalAttrs (ov ? underlayAccess) {
        underlayAccess = ov.underlayAccess;
      };
    in
    normalized;
in
lib.imap0 normalizeOne overlays0
