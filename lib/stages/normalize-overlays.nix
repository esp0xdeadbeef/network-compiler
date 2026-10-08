{ lib }:

siteKey: topo: declared:

let
  validation = import ./normalize-overlays/validation.nix { inherit lib; } siteKey topo;

  inherit (validation)
    validateOverlayPrefix
    resolveTerminateOn
    validateTerm
    ;

  transport0 = declared.transport or { };
  overlays0 = transport0.overlays or [ ];

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

      # FS-370-HDS-010-SDS-010-SMS-020: an explicit overlay prefix that is not
      # modeled as peer/site ownership must fail closed, never be silently
      # dropped. The flat prefixes.ipv4/prefixes.ipv6 shape is the superseded
      # explicit-prefix form (FS-480: overlay reachability is the modeled
      # imported/exported set); reject it with the unbound values named.
      legacyFlatPrefixes =
        if
          builtins.isAttrs rawPrefixes
          && !(rawPrefixes ? imported)
          && !(rawPrefixes ? exported)
          && (rawPrefixes ? ipv4 || rawPrefixes ? ipv6)
        then
          (if builtins.isList (rawPrefixes.ipv4 or null) then map toString rawPrefixes.ipv4 else [ ])
          ++ (if builtins.isList (rawPrefixes.ipv6 or null) then map toString rawPrefixes.ipv6 else [ ])
        else
          [ ];
      _legacyFlatPrefixesBound =
        if legacyFlatPrefixes == [ ] then
          true
        else
          throw (
            builtins.toJSON {
              code = "E_OVERLAY_SOURCE_PREFIX_UNBOUND";
              site = siteKey;
              path = [
                "transport"
                "overlays"
                idx
                "prefixes"
              ];
              message = "overlay '${ov.name or "overlay-${toString idx}"}' declares explicit prefixes ${builtins.toJSON legacyFlatPrefixes}; model those prefixes as peer tenant ownership or the overlay's imported/exported set before exporting overlay reachability";
              hints = [
                "Use prefixes = { imported = { ipv4 = [ ... ]; ipv6 = [ ... ]; }; exported = { ipv4 = [ ... ]; ipv6 = [ ... ]; }; }; and model the prefixes as site/peer ownership."
              ];
            }
          );

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
    builtins.seq _legacyFlatPrefixesBound normalized;
in
lib.imap0 normalizeOne overlays0
