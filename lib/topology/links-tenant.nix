{ lib, addr }:

{
  tenantVlans,
  tenantV4Base,
  ulaPrefix,
  accessNodePrefix,
}:

let
  accessNodeFor = vid: "${accessNodePrefix}-${toString vid}";

  mkTenantLan =
    vid:
    let
      n = accessNodeFor vid;
    in
    {
      name = "access-tenant-${toString vid}";
      value = {
        kind = "lan";
        scope = "internal";
        carrier = "lan";
        vlanId = vid;
        members = [ n ];
        endpoints."${n}" = {
          tenant.vlanId = vid;
          gateway = true;
        };
      };
    };

in
lib.listToAttrs (map mkTenantLan tenantVlans)
