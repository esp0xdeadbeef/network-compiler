{
  lib,
  siteKey,
  declared,
}:

let
  enterprise = declared.enterprise or "default";
  site = declared.siteName or siteKey;
  sortedUnique = values: lib.sort builtins.lessThan (lib.unique values);
in
rec {
  nonEmptyString = value: builtins.isString value && value != "";

  identity =
    endpoint:
    if !builtins.isAttrs endpoint then
      "<missing>"
    else
      "${toString (endpoint.kind or "unknown")}:${toString (endpoint.name or "unknown")}";

  candidateId =
    service:
    "${toString (service.name or "unknown")}@${toString (service.providerNode or "unknown")}";

  inherit sortedUnique;
  sortRecords = values: lib.sort (a: b: builtins.toJSON a < builtins.toJSON b) values;

  containsLiteralFields =
    value:
    builtins.isAttrs value
    && builtins.any (name: builtins.hasAttr name value) [
      "address"
      "addresses"
      "host"
      "ipv4"
      "ipv6"
      "resolverAddress"
    ];

  warning =
    {
      code,
      requester,
      resolverService ? "<missing>",
      resolverNode ? null,
      family ? null,
      candidateIds ? [ ],
      context ? null,
    }:
    {
      traceId =
        if lib.hasPrefix "DNS_CORE_" code then
          "FS-525-HDS-010-SDS-010-SMS-010"
        else
          "FS-540-HDS-010-SDS-010-SMS-020";
      inherit code enterprise site requester resolverService;
      candidateIds = sortedUnique candidateIds;
      disposition = "fail-closed";
    }
    // lib.optionalAttrs (resolverNode != null) { inherit resolverNode; }
    // lib.optionalAttrs (family != null) { inherit family; }
    // lib.optionalAttrs (context != null) { inherit context; };
}
