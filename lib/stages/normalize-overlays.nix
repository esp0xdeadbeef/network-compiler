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

      normalizePrefixFamily =
        family: raw:
        let
          value = raw.${family} or [ ];
        in
        if !(builtins.isList value) then
          throw (
            builtins.toJSON {
              code = "E_OVERLAY_PREFIXES_SHAPE";
              site = siteKey;
              path = [
                "transport"
                "overlays"
                idx
                "prefixes"
                family
              ];
              message = "overlay prefixes.${family} must be a list of CIDR strings";
              hints = [ "Use prefixes.${family} = [ \"<cidr>\" ];" ];
            }
          )
        else
          map (validateOverlayPrefix idx family) (map toString value);

      rawPrefixes = ov.prefixes or null;

      imported0 = if builtins.isAttrs rawPrefixes then rawPrefixes.imported or { } else { };
      exported0 = if builtins.isAttrs rawPrefixes then rawPrefixes.exported or { } else { };

      prefixes =
        if rawPrefixes == null then
          null
        else if !(builtins.isAttrs rawPrefixes) then
          throw (
            builtins.toJSON {
              code = "E_OVERLAY_PREFIXES_SHAPE";
              site = siteKey;
              path = [
                "transport"
                "overlays"
                idx
                "prefixes"
              ];
              message = "overlay prefixes must be an attrset with imported/exported families";
              hints = [
                "Use prefixes = { imported = { ipv4 = [ ... ]; ipv6 = [ ... ]; }; exported = { ipv4 = [ ... ]; ipv6 = [ ... ]; }; };"
              ];
            }
          )
        else
          {
            imported = {
              ipv4 = normalizePrefixFamily "ipv4" imported0;
              ipv6 = normalizePrefixFamily "ipv6" imported0;
            };
            exported = {
              ipv4 = normalizePrefixFamily "ipv4" exported0;
              ipv6 = normalizePrefixFamily "ipv6" exported0;
            };
          };

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
      }
      // lib.optionalAttrs (prefixes != null) {
        inherit prefixes;
      };
    in
    normalized;
in
lib.imap0 normalizeOne overlays0
