{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
in
# FS-620-HDS-010-SDS-010-SMS-030: underlay authority rejection with specific diagnostics
siteKey: serviceName: policy:
let
  isResolverService =
    builtins.elem (policy.serviceClass or "") [
      "resolver"
      "dns"
      "discovery"
    ];
  code =
    if isResolverService then
      "UNDERLAY_USED_AS_RESOLVER_OR_DISCOVERY_AUTHORITY"
    else
      "UNDERLAY_USED_AS_TENANT_PAYLOAD_AUTHORITY";
  message =
    if isResolverService then
      "service '${serviceName}' attempts to use overlay/bootstrap underlay reachability as resolver or discovery authority; underlay reachability must not become client, tenant, resolver, discovery, management, or payload authority"
    else
      "service '${serviceName}' attempts to use provider underlay reachability as tenant payload authority between scopes without a modeled tenant or shared-service allow; underlay reachability must not become client, tenant, resolver, discovery, management, or payload authority";
in
ensure (!(has "inferAuthorityFromUnderlay" policy && policy.inferAuthorityFromUnderlay == true)) {
  inherit code;
  site = siteKey;
  path = [
    "communicationContract"
    "services"
    serviceName
    "servicePolicy"
    "inferAuthorityFromUnderlay"
  ];
  inherit message;
  hints = [
    "Do not derive client, tenant, resolver, discovery, management, payload, or reverse-initiation authority from underlay reachability."
    "Underlay reachability used to establish provider tunnels, overlays, or relays is separate from modeled authority records."
  ];
}
