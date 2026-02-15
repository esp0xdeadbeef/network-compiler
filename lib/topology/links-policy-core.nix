{ lib, addr }:

{
  corePolicyTransitVlan,
  tenantV4Base,
  ulaPrefix,
  policyNodeName,
  coreNodeName,
}:

let
  members = [
    policyNodeName
    coreNodeName
  ];
  lname = "policy-core";
in
{
  policy-core = {
    kind = "p2p";
    scope = "internal";
    carrier = "lan";
    vlanId = corePolicyTransitVlan;

    name = lname;

    inherit members;

    endpoints = {
      "${policyNodeName}" = {
        addr4 = addr.mkP2P4 {
          v4Base = tenantV4Base;
          vlanId = corePolicyTransitVlan;
          inherit members;
          node = policyNodeName;
        };
        addr6 = addr.mkP2P6 {
          inherit ulaPrefix;
          vlanId = corePolicyTransitVlan;
          inherit members;
          node = policyNodeName;
        };
      };

      "${coreNodeName}" = {
        addr4 = addr.mkP2P4 {
          v4Base = tenantV4Base;
          vlanId = corePolicyTransitVlan;
          inherit members;
          node = coreNodeName;
        };
        addr6 = addr.mkP2P6 {
          inherit ulaPrefix;
          vlanId = corePolicyTransitVlan;
          inherit members;
          node = coreNodeName;
        };
      };
    };
  };
}
