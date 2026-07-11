{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
in
# FS-590-HDS-010-SDS-010-SMS-040: discovery authority inference denial
# with specific diagnostic codes for DNS record and host placement inference
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

  dnsRecordCheck =
    checkField "inferDiscoveryFromDnsRecord" "DNS_RECORD_NOT_DISCOVERY_AUTHORITY"
      "service '${serviceName}' unicast DNS record presence must not create discovery authority; DNS records, route availability, and payload reachability are separate from discovery authority"
      [
        "Unicast DNS A or AAAA records are for name resolution, not service discovery authority."
        "Model discovery relationships explicitly; do not infer discovery authority from DNS record visibility."
      ];

  hostPlacementCheck =
    checkField "inferDiscoveryFromHostPlacement" "HOST_PLACEMENT_NOT_DISCOVERY_AUTHORITY"
      "service '${serviceName}' shared host placement must not create discovery authority; co-location, route availability, and service existence are separate from discovery authority"
      [
        "Co-located services on the same host or bridge do not implicitly create discovery relationships."
        "Model discovery relationships explicitly; do not infer discovery authority from shared host placement."
      ];
in
builtins.deepSeq [ dnsRecordCheck hostPlacementCheck ] true
