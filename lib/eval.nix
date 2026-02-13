{ lib }:

let
  mkWanLinks =
    wan:
    if wan == null then
      { }
    else
      lib.mapAttrs (name: w: {
        kind = "wan";
        carrier = "wan";
        vlanId = w.vlanId or 6;
        name = "wan-${name}";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          routes4 = lib.optional (w ? ip4) { dst = "0.0.0.0/0"; };
          routes6 = lib.optional (w ? ip6) { dst = "::/0"; };
        }
        // lib.optionalAttrs (w ? ip4) { addr4 = w.ip4; }
        // lib.optionalAttrs (w ? ip6) { addr6 = w.ip6; };
      }) wan;

  evalFromInput =
    {
      tenantVlans,
      policyAccessTransitBase,
      corePolicyTransitVlan,
      ulaPrefix,
      tenantV4Base,

      policyAccessOffset ? 0,
      policyNodeName ? "s-router-policy-only",
      coreNodeName ? "s-router-core-wan",
      accessNodePrefix ? "s-router-access-",
      domain ? "lan.",
      reservedVlans ? [ 1 ],
      forbiddenVlanRanges ? [ ],
      defaultRouteMode ? "default",
      links ? { },
      wan ? null,
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
        inherit defaultRouteMode;
        links = (topoRaw.links or { }) // links // (mkWanLinks wan);
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
  topoInput = if args ? topology then args.topology else args;

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
