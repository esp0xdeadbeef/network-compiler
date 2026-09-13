{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };

  normalise = d: if builtins.substring (builtins.stringLength d - 1) 1 d == "." then d else "${d}.";

in
{

  resolve =
    {
      site,
      tenant,
    }:
    let
      name = tenant.name;
      explicit = tenant.dnsDomain or null;
      zone = tenant.zone or null;
      dnsZones = site.dnsZones or { };
      derived =
        if zone == null then
          null
        else if dnsZones ? ${zone} && (dnsZones.${zone}.suffix or null) != null then
          normalise "${name}.${dnsZones.${zone}.suffix}"
        else
          util.throwError {
            code = "E_TENANT_DNS_ZONE_UNKNOWN";
            site = site.siteName or null;
            path = [
              "ownership"
              "prefixes"
              name
              "zone"
            ];
            message = "tenant '${name}' references unknown DNS zone '${zone}'";
            hints = [ "Add site.dnsZones.${zone}.suffix, or set an explicit dnsDomain on the tenant." ];
          };
    in
    if explicit != null && derived != null && normalise explicit != derived then
      util.throwError {
        code = "E_TENANT_DNS_DOMAIN_ZONE_CONFLICT";
        site = site.siteName or null;
        path = [
          "ownership"
          "prefixes"
          name
        ];
        message = "tenant '${name}' has an explicit dnsDomain '${explicit}' that disagrees with zone '${zone}' (${derived})";
        hints = [ "Keep either the explicit dnsDomain or the zone reference, not both." ];
      }
    else if explicit != null then
      normalise explicit
    else if derived != null then
      derived
    else
      null;

  resolveSearchDomains =
    {
      site,
      tenant,
    }:
    let
      zone = tenant.zone or null;
      dnsZones = site.dnsZones or { };
      own = import ./dns-domain.nix { inherit lib; };
      ownDomain = own.resolve { inherit site tenant; };
      shared =
        if zone != null && dnsZones ? ${zone} && (dnsZones.${zone}.suffix or null) != null then
          normalise dnsZones.${zone}.suffix
        else
          null;
    in
    if ownDomain == null then
      [ ]
    else if shared != null && shared != ownDomain then
      [
        ownDomain
        shared
      ]
    else
      [ ownDomain ];
}
