{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;
  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
in
# FS-630-HDS-010-SDS-010-SMS-020: printer payload authorization
# with specific diagnostic codes for printer payload validation
siteKey: serviceName: policy:
let
  serviceClass = policy.serviceClass or "";
  isPrinterService = builtins.elem serviceClass [ "printer" ];

  hasDiscovery = has "discovery" policy;
  hasPayloadAttr = has "payload" policy;

  hasPayloadWithoutDirection =
    has "payload" policy
    && has "protocol" (policy.payload or { })
    && has "ports" (policy.payload or { })
    && !(has "direction" (policy.payload or { }));

  # SN2: Printer service with discovery but no payload field at all
  checkPayloadInferredFromDiscovery =
    ensure (!(isPrinterService && hasDiscovery && !hasPayloadAttr)) {
      code = "PAYLOAD_AUTHORIZATION_INFERRED_FROM_DISCOVERY";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
      ];
      message = "service '${serviceName}' printer has discovery but no payload protocol, port, direction, returnBehavior, or exposure class; printer payload authorization must be explicit and not inferred from discovery";
      hints = [
        "Model printer payload protocol, ports, direction, returnBehavior, and exposure class explicitly."
        "Printer discovery visibility and printer payload authorization are separate authority classes."
        "The SMS-020 printer payload authorization module requires complete payload tuple fields."
      ];
    };

  # SN1: Printer payload has protocol+ports but missing direction field
  checkMissingPayloadDirection =
    ensure (!(isPrinterService && hasPayloadWithoutDirection)) {
      code = "MISSING_PAYLOAD_DIRECTION";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
        "payload"
        "direction"
      ];
      message = "service '${serviceName}' printer payload has protocol and ports but is missing direction; printer payload direction must be explicit and not defaulted to bidirectional";
      hints = [
        "Set payload.direction to an explicit value (e.g. 'requester-to-responder')."
        "Defaulting to bidirectional is not allowed for printer payload authorization."
        "The SMS-020 printer payload authorization module requires explicit payload direction."
      ];
    };
in
builtins.deepSeq [ checkPayloadInferredFromDiscovery checkMissingPayloadDirection ] true
