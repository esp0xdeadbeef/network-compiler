{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;

  # Check if any deniedPath entry matches a specific from tenant name
  hasDeniedPathForName =
    deniedPaths: tenantName:
    builtins.any
      (entry:
        (entry.from.kind or "") == "tenant" &&
        (entry.from.name or "") == tenantName)
      deniedPaths;
in
siteKey: serviceName: policy:

let
  serviceClass = policy.serviceClass or "";

  # Only active for media-receiver service class
  isMediaReceiver = serviceClass == "media-receiver";

  deniedPaths = policy.deniedPaths or [ ];

  # Guest-to-trusted path: any deniedPath entry with from=tenant name=guest
  hasGuestDenied = hasDeniedPathForName deniedPaths "guest";

  # SN1: guest-to-trusted denied path omitted for media-receiver
  requireGuestDeniedPath = ensure (if isMediaReceiver then hasGuestDenied else true) {
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
  # Check for fields that would indicate denied-path records being overwritten
  overwriteFields = [
    "overwriteDeniedPaths"
    "clearDeniedPaths"
    "resetDeniedPaths"
    "inferDeniedPathsFromPayload"
  ];
  hasOverwrite = builtins.any (f: has f policy && policy.${f} == true) overwriteFields;

  requireDeniedPathNotOverwritten = ensure (if isMediaReceiver then !hasOverwrite else true) {
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
builtins.deepSeq
  [ requireGuestDeniedPath requireDeniedPathNotOverwritten ]
  true
