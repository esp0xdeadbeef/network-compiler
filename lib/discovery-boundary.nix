{ lib }:

# FS-610-HDS-010-SDS-010-SMS-010: Discovery Relay Boundary Input Module.
#
# A cross-scope discovery relationship (mDNS, SSDP, broadcast, multicast) is not
# described by the reachability a unicast route gives. It carries its own
# boundary: who asks, who answers, for which service and protocol family, in
# which direction, through which relay or proxy role, and how far the propagation
# may reach.
#
# This module validates that input and emits the platform-neutral contract. It
# refuses rather than default-fills: a relationship missing its relay role or
# propagation boundary is rejected, and a unicast route is never allowed to stand
# in for discovery authority.

let
  util = import ./correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  isNonEmptyString = value: builtins.isString value && value != "";

  require =
    cond: code: path: site: message: hints:
    ensure cond {
      inherit code;
      inherit path site message hints;
    };

  # All seven facts the SMS requires on a cross-scope discovery relationship.
  requiredFields = [
    "requesterScope"
    "responderScope"
    "serviceType"
    "protocolFamily"
    "direction"
    "relayRole"
    "maxPropagationBoundary"
  ];

  validDirections = [
    "request"
    "response"
    "bidirectional"
  ];

  validFamilies = [
    "mdns"
    "ssdp"
    "broadcast"
    "multicast"
  ];
in
{
  inherit requiredFields;

  build =
    {
      site ? null,
      relationships ? [ ],
      # A unicast route observed between two scopes. It is only ever evidence of
      # reachability, never of discovery authority.
      unicastRoutes ? [ ],
    }:
    let
      checked = lib.imap0 (
        idx: rel:
        let
          path = [
            "discoveryRelationships"
            idx
          ];
          missing = lib.filter (
            field:
            let
              value = rel.${field} or null;
            in
            if field == "maxPropagationBoundary" then
              !(builtins.isInt value) || value < 0
            else
              !isNonEmptyString value
          ) requiredFields;
          label =
            "discovery relationship ${builtins.toJSON (rel.requesterScope or "?")} -> ${builtins.toJSON (
              rel.responderScope or "?"
            )}";
        in
        {
          _complete = require (missing == [ ])
            "E_INCOMPLETE_DISCOVERY_BOUNDARY"
            path
            site
            "${label} omits its ${builtins.concatStringsSep ", " missing}"
            [
              "Name requester scope, responder scope, service type, protocol family, direction, relay or proxy role, and maximum propagation boundary."
              "A discovery boundary is declared, never default-filled."
            ];

          _direction = require (
            !(rel ? direction) || builtins.elem rel.direction validDirections
          )
            "E_AMBIGUOUS_DISCOVERY_BOUNDARY"
            (path ++ [ "direction" ])
            site
            "${label} declares direction '${toString (rel.direction or null)}', which is not one of ${builtins.concatStringsSep ", " validDirections}"
            [ "Declare one direction so the relay, proxy, reflection or flooding input is unambiguous." ];

          _family = require (
            !(rel ? protocolFamily) || builtins.elem rel.protocolFamily validFamilies
          )
            "E_AMBIGUOUS_DISCOVERY_BOUNDARY"
            (path ++ [ "protocolFamily" ])
            site
            "${label} declares protocol family '${toString (
              rel.protocolFamily or null
            )}', which is not one of ${builtins.concatStringsSep ", " validFamilies}"
            [ "Declare one protocol family so the discovery boundary is unambiguous." ];

          # A relay role must be a real service, not a synonym for "there is a
          # route". A relationship whose only support is a unicast route has no
          # discovery boundary at all.
          _notUnicastOnly = require (isNonEmptyString (rel.relayRole or null))
            "E_UNICAST_ROUTE_NOT_DISCOVERY_BOUNDARY"
            path
            site
            "${label} has a unicast route but no discovery relay, proxy or reflection boundary"
            [ "Model the relay, proxy or reflection boundary that carries the discovery traffic." ];
        }
      ) relationships;

      contract = map (rel: {
        inherit (rel)
          requesterScope
          responderScope
          serviceType
          protocolFamily
          direction
          relayRole
          maxPropagationBoundary
          ;
      }) (lib.filter (rel: builtins.isAttrs rel) relationships);

      _validate = builtins.deepSeq (map (rel: rel._complete) checked) (
        builtins.deepSeq (map (rel: rel._direction) checked) (
          builtins.deepSeq (map (rel: rel._family) checked) (builtins.deepSeq (map (rel: rel._notUnicastOnly) checked) true)
        )
      );
    in
    {
      inherit contract requiredFields;
      validations = { inherit _validate; };
      inherit _validate;
    };
}
