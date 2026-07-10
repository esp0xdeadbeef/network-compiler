{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;

  # Check if a deniedPath entry matches a specific from-to pattern
  hasDeniedPathFor =
    deniedPaths: fromKind: fromName: toKind: toName:
    builtins.any
      (entry:
        (entry.from.kind or "") == fromKind &&
        (entry.from.name or "") == fromName &&
        (entry.to.kind or "") == toKind &&
        (entry.to.name or "") == toName)
      deniedPaths;
in
siteKey: serviceName: policy:

let
  serviceClass = policy.serviceClass or "";

  # Only active for media-receiver service class
  isMediaReceiver = serviceClass == "media-receiver";

  deniedPaths = policy.deniedPaths or [ ];

  # Guest-to-trusted path: from tenant=guest to tenant=trusted or to service=*
  hasGuestToTrustedDenied =
    hasDeniedPathFor deniedPaths "tenant" "guest" "tenant" "trusted" ||
    hasDeniedPathFor deniedPaths "tenant" "guest" "service" (serviceName) ||
    builtins.any
      (entry:
        (entry.from.kind or "") == "tenant" &&
        (entry.from.name or "") == "guest")
      deniedPaths;

  # Reverse discovery / broad multicast: from tenant=media or similar untrusted scope to trusted/controller
  hasReverseDiscoveryDenied =
    builtins.any
      (entry:
        (entry.reason or "") == "reverse-discovery-denied" ||
        (entry.reason or "") == "broad-multicast-denied" ||
        (entry.reason or "") == "media-to-controller-denied")
      deniedPaths;

  # SN1: guest-to-trusted denied path omitted for media-receiver
  requireGuestDeniedPath = ensure isMediaReceiver -> hasGuestToTrustedDenied {
    code = "MEDIA_DENIED_PATH_MISSING";
    site = siteKey;
    path = [
      "communicationContract"
      "services"
      serviceName
      "servicePolicy"
      "deniedPaths"
    ];
    message = "media-receiver service '${serviceName}' is missing denied-path data for guest-to-trusted or guest scope; media receivers must explicitly deny guest, media, untrusted, and unrelated tenant access";
    hints = [
      "Add a deniedPath entry with from = { kind = \"tenant\"; name = \"guest\"; } naming the denied scope and negative probe."
    ];
  };

  # SN2: denied path overwritten by payload authorization
  # Check for fields that would indicate payload auth trying to overwrite denied-path records
  requireDeniedPathNotOverwritten = ensure isMediaReceiver -> !(has "inferDeniedPathsFromPayload" policy && policy.inferDeniedPathsFromPayload == true) {
    code = "MEDIA_DENIED_PATH_OVERWRITTEN";
    site = siteKey;
    path = [
      "communicationContract"
      "services"
      serviceName
      "servicePolicy"
    ];
    message = "media-receiver service '${serviceName}' denied-path data is being overwritten by payload authorization; denied-path records must be preserved independently from payload authorization";
    hints = [
      "Remove the inferDeniedPathsFromPayload field or set it to false."
      "Declare deniedPaths explicitly with guest-to-trusted, reverse-discovery, and broad-multicast denial records."
    ];
  };

  # Also check for an explicit overwriteDeniedPaths or clearDeniedPaths flag
  requireNoOverwrite =
    let
      overwriteFields = [
        "overwriteDeniedPaths"
        "clearDeniedPaths"
        "resetDeniedPaths"
        "inferDeniedPathsFromPayload"
      ];
      hasOverwrite = builtins.any (f: has f policy && policy.${f} == true) overwriteFields;
    in
    ensure isMediaReceiver -> !hasOverwrite {
      code = "MEDIA_DENIED_PATH_OVERWRITTEN";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
      ];
      message = "media-receiver service '${serviceName}' denied-path data is being overwritten; denied-path records must be preserved independently from payload authorization";
      hints = [
        "Remove the overwrite/clear/infer flag from the service policy."
        "Denied-path records for guest-to-trusted, reverse-discovery, and broad-multicast must remain as explicitly declared data."
      ];
    };

in
if isMediaReceiver then
  builtins.deepSeq
    [ requireGuestDeniedPath requireDeniedPathNotOverwritten requireNoOverwrite ]
    true
else
  true
