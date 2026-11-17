{
  lib,
  normalizeUplinksForNode,
  ensure,
}:

siteKey: nodes: coreNodes:
{
  overlayEndpointNodes ? [ ],
  overlays ? [ ],
}:

let
  # FS-255: a core models two legs -- the fabric ingress (its selector link)
  # and one reachability leg. The reachability leg is either a modeled uplink
  # or, for a core whose exit is a selected remote tenant context, the
  # `underlayAccess` carriage attachment that carries the tunnel (FS-260).
  tenantAttachmentsOf =
    name:
    map (attachment: toString (attachment.name or ""))
      (
        builtins.filter
          (attachment: (attachment.kind or null) == "tenant")
          (nodes.${name}.attachments or [ ])
      );

  carriageOf =
    name:
    builtins.concatMap
      (overlay:
        let
          targets =
            let
              t = overlay.terminateOn or overlay.targets or [ ];
            in
            if builtins.isList t then map toString t else [ (toString t) ];
          underlayAccess = overlay.underlayAccess or { };
        in
        if
          builtins.elem name targets
          && (underlayAccess.kind or null) == "tenant"
          && (underlayAccess.name or null) != null
        then
          [
            {
              overlay = toString (overlay.name or "?");
              tenant = toString underlayAccess.name;
            }
          ]
        else
          [ ])
      overlays;

  attached =
    { carriage, tenants }:
    builtins.elem carriage.tenant tenants;
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value =
      let
        uplinks = normalizeUplinksForNode.forNodeList siteKey name (nodes.${name}.uplinks or null);
        isOverlayEndpoint = builtins.elem name overlayEndpointNodes;
        carriers = carriageOf name;
        tenants = tenantAttachmentsOf name;
        realizedCarriage = builtins.filter (carriage: attached { inherit carriage tenants; }) carriers;
        missingCarriage = carriers != [ ] && realizedCarriage == [ ];
        required = ensure (builtins.length uplinks > 0 || realizedCarriage != [ ]) (
          if isOverlayEndpoint && missingCarriage then
            let
              carriage = builtins.head carriers;
            in
            {
              code = "E_CORE_CARRIAGE_REQUIRED";
              site = siteKey;
              path = [
                "topology"
                "nodes"
                name
                "attachments"
              ];
              message =
                "core node '${name}' terminates overlay '${carriage.overlay}' but models neither an uplink nor the underlayAccess carriage attachment '${carriage.tenant}'; a core exists to make something reachable, so one leg is not a core";
              hints = [
                "Add attachments = [ { kind = \"tenant\"; name = \"${carriage.tenant}\"; } ]; to topology.nodes.${name} so the tunnel's underlay carriage is a modeled host attachment, or declare an uplink on the node."
                "FS-255/FS-260: the remote-egress exemption removes the local exit, not the carriage surface."
              ];
            }
          else
            {
              code = "E_CORE_UPLINKS_REQUIRED";
              site = siteKey;
              path = [
                "topology"
                "nodes"
                name
                "uplinks"
              ];
              message = "core node '${name}' must define at least one uplink or be a modeled overlay/remote-egress endpoint with its underlayAccess carriage attachment";
              hints = [
                "Set topology.nodes.${name}.uplinks = { uplink0 = { ipv4 = [\"0.0.0.0/0\"]; ipv6 = [\"::/0\"]; }; }, or model an overlay whose terminateOn is '${name}' and attach the tenant its underlayAccess names."
              ];
            }
        );
      in
      if required then uplinks else uplinks;
  }) coreNodes
)
