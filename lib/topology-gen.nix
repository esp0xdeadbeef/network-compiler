{ lib }:

{
  tenantVlans,
  policyAccessTransitBase,
  corePolicyTransitVlan,

  ulaPrefix ? "fd42:dead:beef",
  tenantV4Base ? "10.10",
}:

let
  policyNode = "s-router-policy-only";
  coreNode = "s-router-core-wan";

  accessNodeFor = vid: "s-router-access-${toString vid}";

  minTenantVlan =
    if tenantVlans == [ ] then
      throw "topology-gen: tenantVlans must not be empty"
    else
      lib.foldl' (a: b: if b < a then b else a)
        (lib.head tenantVlans)
        (lib.tail tenantVlans);

  accessTransitVlanFor =
    vid: policyAccessTransitBase + (vid - minTenantVlan);

  strip = s: builtins.elemAt (lib.splitString "." s) 0;

  mkAccess =
    vid: {
      name = accessNodeFor vid;
      value = {
        ifs = { lan = "lan0"; };
      };
    };

  nodes =
    {
      "${coreNode}" = { ifs = { lan = "lan0"; wan = "wan0"; }; };
      "${policyNode}" = { ifs = { lan = "lan0"; }; };
    }
    // (lib.listToAttrs (map mkAccess tenantVlans));

  mkTenantLan =
    vid:
    let
      n = accessNodeFor vid;
      lname = "access-tenant-${toString vid}";
    in
    {
      name = lname;
      value = {
        kind = "lan";
        carrier = "lan";
        vlanId = vid;
        name = lname;
        members = [ n ];
        endpoints = {
          "${n}" = {
            tenant = { vlanId = vid; };
            gateway = true;

            # deterministic gateway IPs so routing phase has addr4/addr6
            addr4 = "${tenantV4Base}.${toString vid}.1/24";
            addr6 = "${ulaPrefix}:${toString vid}::1/64";
          };
        };
      };
    };

  mkPolicyAccess =
    vid:
    let
      access = accessNodeFor vid;
      vlanId = accessTransitVlanFor vid;
      lname = "policy-access-${toString vid}";

      access4 = "${tenantV4Base}.${toString vid}.2/30";
      policy4 = "${tenantV4Base}.${toString vid}.3/30";

      access6 = "${ulaPrefix}:${toString vid}:1::2/64";
      policy6 = "${ulaPrefix}:${toString vid}:1::3/64";
    in
    {
      name = lname;
      value = {
        kind = "p2p";
        carrier = "lan";
        vlanId = vlanId;
        name = lname;
        members = [ policyNode access ];
        endpoints = {
          "${access}" = {
            tenant = { vlanId = vid; };
            addr4 = access4;
            addr6 = access6;
          };
          "${policyNode}" = {
            addr4 = policy4;
            addr6 = policy6;
          };
        };
      };
    };

  links =
    (lib.listToAttrs (map mkTenantLan tenantVlans))
    // (lib.listToAttrs (map mkPolicyAccess tenantVlans))
    // {
      policy-core = {
        kind = "p2p";
        carrier = "lan";
        vlanId = corePolicyTransitVlan;
        name = "policy-core";
        members = [ policyNode coreNode ];
        endpoints = {
          "${policyNode}" = {
            addr4 = "${tenantV4Base}.255.2/30";
            addr6 = "${ulaPrefix}:ffff::2/64";
          };
          "${coreNode}" = {
            addr4 = "${tenantV4Base}.255.1/30";
            addr6 = "${ulaPrefix}:ffff::1/64";
          };
        };
      };
    };

in
{
  inherit ulaPrefix tenantV4Base;
  domain = "lan.";
  inherit nodes links;
}
