{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
in
# FS-610-HDS-010-SDS-010-SMS-020: discovery boundary decision separation
# with specific diagnostic codes for each authorization leak class
siteKey: serviceName: policy:
let
  checkField = field: code: message: hints:
    ensure (!(has field policy && policy.${field} == true)) {
      inherit code;
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
        field
      ];
      inherit message;
      inherit hints;
    };

  payloadCheck =
    checkField "inferPayloadFromDiscovery" "DISCOVERY_PAYLOAD_AUTHORIZATION_LEAK"
      "service '${serviceName}' discovery visibility attempts to grant unauthorized payload authorization; discovery visibility must stay independent from payload authorization"
      [
        "Model payload reachability explicitly through payload policy records, not through discovery visibility."
        "Discovery visibility and payload authorization are separate authority classes."
      ];

  managementCheck =
    checkField "inferManagementFromDiscovery" "DISCOVERY_MANAGEMENT_AUTHORIZATION_LEAK"
      "service '${serviceName}' discovery visibility attempts to grant unauthorized management authorization; discovery visibility must stay independent from management-plane access"
      [
        "Model management access explicitly through managementAccessPolicy records, not through discovery visibility."
        "Discovery visibility and management authorization are separate authority classes."
      ];

  reverseDiscoveryCheck =
    checkField "inferReverseInitiationFromDiscovery" "DISCOVERY_REVERSE_DISCOVERY_AUTHORIZATION_LEAK"
      "service '${serviceName}' discovery visibility attempts to grant unauthorized reverse discovery authorization; discovery visibility must stay independent from reverse discovery and unrelated service authorization"
      [
        "Model reverse discovery paths explicitly as separate authorization records."
        "Discovery visibility, reverse discovery, and unrelated service authorization are separate authority classes."
      ];
in
builtins.deepSeq [ payloadCheck managementCheck reverseDiscoveryCheck ] true
