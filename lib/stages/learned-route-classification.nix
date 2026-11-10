{ lib }:

# FS-482-HDS-010-SDS-010-SMS-030: Learned-Route Classification.
#
# A route learned over BGP (or any runtime routing source) does not establish
# that this model owns the destination. It establishes *conditional* route
# availability: reachable only while the current route-import facts hold. The
# URS requires exactly that reading — "classify the answer as conditional until
# current route-import facts are supplied".
#
# This module therefore keeps the learned-route set on its own surface, apart
# from the owned-prefix surface (which decides prefix authority) and apart from
# the payload-permission surface (which decides whether payload may flow). A
# learned route may never be presented as either.
#
# Nothing here is inferred. A learned route must carry its peer, its address
# family, and an import classification; anything missing is refused rather than
# default-filled, so a route is never silently promoted to owned.

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  isNonEmptyString = value: builtins.isString value && value != "";
  isAttrs = builtins.isAttrs;

  require =
    siteName: cond: code: path: message: hints:
    ensure cond {
      inherit code;
      site = siteName;
      inherit path message hints;
    };

  # The two surfaces a learned route must stay off. A route that names either is
  # being presented as model-owned or as a payload grant.
  ownedPrefixesFor =
    site:
    let
      ownership = site.ownership or { };
      prefixes = ownership.prefixes or [ ];
    in
    lib.concatMap (
      entry:
      lib.concatLists [
        (if isNonEmptyString (entry.ipv4 or null) then [ entry.ipv4 ] else [ ])
        (if isNonEmptyString (entry.ipv6 or null) then [ entry.ipv6 ] else [ ])
      ]
    ) (lib.filter isAttrs prefixes);

  siteKey = site: site.key or "";
in
{
  # `declared` is the user's site input; `semantic` is the normalized view.
  # The learned-route set is observed at the control-plane model boundary and is
  # supplied explicitly — this module never derives it from topology or uplinks.
  build =
    site:
    let
      learned = site.learnedRoutes or [ ];
      ownedPrefixes = ownedPrefixesFor site;
      siteName = siteKey site;

      checked = lib.imap0 (
        idx: route:
        let
          path = [
            "learnedRoutes"
            idx
          ];
          prefix = route.prefix or null;
          peer = route.peer or null;
          family = route.family or null;
          importClassification = route.importClassification or null;

          surfaceIssues =
            lib.concatLists [
              (lib.optional (route.ownedPrefix or false) "owned-prefix")
              (lib.optional (route.payloadPermission or false) "payload-permission")
            ];
        in
        {
          inherit
            prefix
            peer
            family
            importClassification
            ;

          # SN1: a learned route presented as an owned prefix, or whose prefix
          # collides with one this model already owns, is refused naming both the
          # prefix and the peer.
          _ownedConflict = require siteName
            (isNonEmptyString prefix && !(builtins.elem prefix ownedPrefixes) && surfaceIssues == [ ])
            "E_LEARNED_ROUTE_OWNED_PREFIX_CONFLICT"
            path
            (
              if surfaceIssues != [ ] then
                "learned route '${toString prefix}' from peer '${toString peer}' is presented on the ${builtins.concatStringsSep " and " surfaceIssues} surface"
              else
                "learned route '${toString prefix}' from peer '${toString peer}' collides with a model-owned prefix"
            )
            [
              "A BGP-learned route is conditional route availability; it never becomes an owned prefix."
              "Keep the route on the learned-route surface and let the model's own ownership declare authority."
            ];

          # SN2: import classification is required, never default-filled.
          _classified = require siteName
            (isNonEmptyString importClassification && importClassification == "conditional")
            "E_LEARNED_ROUTE_IMPORT_UNCLASSIFIED"
            (path ++ [ "importClassification" ])
            "learned route '${toString prefix}' from peer '${toString peer}' has no 'conditional' import classification"
            [
              "Classify a learned route as conditional route availability until current route-import facts are supplied."
              "Set importClassification = \"conditional\"."
            ];

          # P4: peer and address family must accompany the route.
          _identified = require siteName
            (
              isNonEmptyString peer
              && builtins.elem family [
                "ipv4"
                "ipv6"
              ]
            )
            "E_LEARNED_ROUTE_IDENTITY_MISSING"
            path
            "learned route '${toString prefix}' omits its peer or address family"
            [ "Expose every learned route with its peer and address family." ];
        }
      ) (lib.filter isAttrs learned);

      conditionalAvailability = map (route: {
        inherit (route)
          prefix
          peer
          family
          importClassification
          ;
        availability = "conditional";
        owned = false;
        payloadPermission = false;
      }) checked;

      _validate =
        builtins.deepSeq (map (route: route._ownedConflict) checked)
          (builtins.deepSeq (map (route: route._classified) checked)
            (builtins.deepSeq (map (route: route._identified) checked) true));
    in
    {
      inherit conditionalAvailability;

      # Deliberately empty: the module owns the separation. Routes never reach the
      # owned-prefix or payload-permission surfaces through this record.
      ownedPrefixSurface = [ ];
      payloadPermissionSurface = [ ];

      validations = {
        inherit _validate;
        site = siteName;
      };

      # Exposed so the build model can force it alongside the other stage
      # validations; a learned route is refused before the output is assembled.
      inherit _validate;
    };
}
