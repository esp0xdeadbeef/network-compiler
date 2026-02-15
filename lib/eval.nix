{ lib }:

let
  mkWanLinks =
    coreNodeName: wan:
    if wan == null then
      { }
    else
      lib.mapAttrs (
        ctx: w:
        let
          coreCtx = "${coreNodeName}-${ctx}";

          dhcp = w.dhcp or false;
          acceptRA = w.acceptRA or false;

          wantDefault4 = dhcp || (w ? routes4) || (w ? ip4);
          wantDefault6 = dhcp || acceptRA || (w ? routes6) || (w ? ip6);

          routes4 =
            if w ? routes4 then
              w.routes4
            else if wantDefault4 then
              [ { dst = "0.0.0.0/0"; } ]
            else
              [ ];

          routes6 =
            if w ? routes6 then
              w.routes6
            else if wantDefault6 then
              [ { dst = "::/0"; } ]
            else
              [ ];
        in
        {
          kind = "wan";
          carrier = "wan";
          vlanId = w.vlanId or 6;
          name = "wan-${ctx}";
          members = [ coreNodeName ];
          endpoints."${coreCtx}" = {
            inherit routes4 routes6;
          }
          // lib.optionalAttrs (w ? ip4) { addr4 = w.ip4; }
          // lib.optionalAttrs (w ? ip6) { addr6 = w.ip6; }
          // lib.optionalAttrs (w ? acceptRA) { acceptRA = w.acceptRA; }
          // lib.optionalAttrs (w ? dhcp) { dhcp = w.dhcp; };
        }
      ) wan;

  evalFromInput =
    {
      tenantVlans,
      policyAccessTransitBase,
      corePolicyTransitVlan,
      ulaPrefix,
      tenantV4Base,

      policyAccessOffset ? 0,
      policyNodeName ? "s-router-policy-only",
      coreNodeName ? "s-router-core",
      accessNodePrefix ? "s-router-access",
      domain ? "lan.",
      reservedVlans ? [ 1 ],
      forbiddenVlanRanges ? [ ],
      defaultRouteMode ? "default",
      links ? { },
      wan ? null,
      coreRoutingNodeName ? null,
      ...
    }:

    let
      topoRaw = import ./topology-gen.nix { inherit lib; } {
        inherit
          tenantVlans
          policyAccessTransitBase
          corePolicyTransitVlan
          policyAccessOffset
          policyNodeName
          coreNodeName
          accessNodePrefix
          domain
          reservedVlans
          forbiddenVlanRanges
          ulaPrefix
          tenantV4Base
          ;
      };

      topoWithLinks = topoRaw // {
        inherit defaultRouteMode coreRoutingNodeName;
        links = (topoRaw.links or { }) // links // (mkWanLinks coreNodeName wan);
      };

      topoResolved = import ./topology-resolve.nix {
        inherit lib ulaPrefix tenantV4Base;
      } topoWithLinks;

      compiled = import ./compile/compile.nix {
        inherit lib;
        model = topoResolved;
      };
    in
    compiled;

in

args:
let
  topoInputRaw = if args ? topology then args.topology else args;

  topoInput = if builtins.isFunction topoInputRaw then topoInputRaw { } else topoInputRaw;

  isResolved =
    topoInput ? nodes
    && topoInput ? links
    && topoInput ? ulaPrefix
    && topoInput ? tenantV4Base
    && !(topoInput ? tenantVlans);

in
if isResolved then
  import ./compile/compile.nix {
    inherit lib;
    model = topoInput;
  }
else
  evalFromInput topoInput
