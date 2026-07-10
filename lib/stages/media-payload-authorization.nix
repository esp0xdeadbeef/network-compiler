{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;
  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
in
# FS-640-HDS-010-SDS-010-SMS-020: media payload authorization
# with specific diagnostic codes for media payload validation
siteKey: serviceName: policy:
let
  serviceClass = policy.serviceClass or "";
  isMediaService = builtins.elem serviceClass [ "media-receiver" "media" ];

  hasDiscovery = has "discovery" policy;
  hasPayloadAttr = has "payload" policy;

  hasPartialPayload =
    has "payload" policy
    && has "protocol" (policy.payload or { })
    && has "ports" (policy.payload or { });

  hasCloudDependency = has "cloudDependency" policy;
  hasReturnBehavior = has "payload" policy && has "returnBehavior" (policy.payload or { });

  # SN1: Media service with discovery but no payload field at all
  checkPayloadInferredFromDiscovery =
    ensure (!(isMediaService && hasDiscovery && !hasPayloadAttr)) {
      code = "MEDIA_PAYLOAD_INFERRED_FROM_DISCOVERY";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
      ];
      message = "service '${serviceName}' has discovery but no payload protocol, port, direction, returnBehavior, or exposure class; media payload authorization must be explicit and not inferred from discovery";
      hints = [
        "Model media payload protocol, ports, direction, returnBehavior, and exposure class explicitly."
        "Discovery visibility and payload authorization are separate authority classes."
        "The SMS-020 media payload authorization module requires complete payload tuple fields."
      ];
    };

  # SN2: Incomplete payload tuple (protocol+ports present, but cloudDependency or returnBehavior missing)
  missingFields =
    (if !hasCloudDependency then [ "cloudDependency" ] else [ ])
    ++ (if !hasReturnBehavior then [ "payload.returnBehavior" ] else [ ]);

  checkPayloadTupleIncomplete =
    ensure (!(isMediaService && hasPartialPayload && missingFields != [ ])) {
      code = "MEDIA_PAYLOAD_TUPLE_INCOMPLETE";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
      ];
      message = "service '${serviceName}' media payload tuple is incomplete: missing ${lib.concatStringsSep ", " missingFields}";
      hints = [
        "Add cloudDependency classification (none, optional, or required) to the service policy."
        "Add payload.returnBehavior (established-only, static, or na) to the payload record."
        "The SMS-020 media payload authorization module requires complete payload tuple fields."
      ];
    };
in
builtins.deepSeq [ checkPayloadInferredFromDiscovery checkPayloadTupleIncomplete ] true
