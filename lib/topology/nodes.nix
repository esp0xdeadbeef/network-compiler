{ lib }:

{
  tenantVlans,
  accessNodePrefix,
  policyNodeName,
  coreNodeName,
}:

let
  baseIfs = {
    lan = "lan";
  };

  accessNodeFor = vid: "${accessNodePrefix}-${toString vid}";

  mkAccess = vid: {
    name = accessNodeFor vid;
    value = {
      ifs = baseIfs // {
        "lan${toString vid}" = "lan-${toString vid}";
      };
    };
  };

in
{
  "${coreNodeName}" = {
    ifs = baseIfs;
  };
  "${policyNodeName}" = {
    ifs = baseIfs;
  };
}
// (lib.listToAttrs (map mkAccess tenantVlans))
