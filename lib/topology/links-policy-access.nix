{ lib, addr }:

{
  tenantVlans,
  tenantV4Base,
  ulaPrefix,
  policyAccessTransitBase,
  policyAccessOffset,
  accessNodePrefix,
  policyNodeName,
}:

let
  accessNodeFor = vid: "${accessNodePrefix}-${toString vid}";
  transitFor = vid: policyAccessTransitBase + policyAccessOffset + vid;

  mk =
    vid:
    let
      access = accessNodeFor vid;
      vlanId = transitFor vid;
      members = [
        policyNodeName
        access
      ];
    in
    {
      name = "policy-access-${toString vid}";
      value = {
        kind = "p2p";
        scope = "internal";
        carrier = "lan";
        inherit vlanId members;
        endpoints = {
          "${access}" = {
            tenant.vlanId = vid;
            addr4 = addr.mkP2P4 {
              v4Base = tenantV4Base;
              inherit vlanId members;
              node = access;
            };
            addr6 = addr.mkP2P6 {
              inherit ulaPrefix vlanId members;
              node = access;
            };
          };
          "${policyNodeName}" = {
            addr4 = addr.mkP2P4 {
              v4Base = tenantV4Base;
              inherit vlanId members;
              node = policyNodeName;
            };
            addr6 = addr.mkP2P6 {
              inherit ulaPrefix vlanId members;
              node = policyNodeName;
            };
          };
        };
      };
    };

in
lib.listToAttrs (map mk tenantVlans)
