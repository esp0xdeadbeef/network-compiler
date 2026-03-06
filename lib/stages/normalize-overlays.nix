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

  resolveTerminateOn =
    idx: ov:
    if ov ? terminateOn then
      ov.terminateOn
    else if builtins.length coreNodes == 1 then
      builtins.elemAt coreNodes 0
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
          hints = [ "Set terminateOn to a core node." ];
        }
      );

  normalizeOne =
    idx: ov:
    let
      term = resolveTerminateOn idx ov;

      _termExists =
        if builtins.elem term nodeNames then
          true
        else
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
          );

      _termIsCore =
        if builtins.elem term coreNodes then
          true
        else
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
          );
    in
    builtins.deepSeq { inherit _termExists _termIsCore; } {
      name = ov.name or "overlay-${toString idx}";
      peerSite = ov.peerSite or ov.peer or ov.toSite;
      terminateOn = term;
      mustTraverse = ov.mustTraverse or [ ];
    };

in
lib.imap0 normalizeOne overlays0
