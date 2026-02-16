{ lib, model }:

let
  links = model.links or { };

  allVlans = lib.unique (
    lib.concatMap (
      l:
      let
        kind = l.kind or null;
      in
      lib.optional (l ? vlanId && kind != "wan") l.vlanId
    ) (lib.attrValues links)
  );

  reserved = model.reservedVlans or [ 1 ];

  forbiddenRanges =
    if !(model ? forbiddenVlanRanges) then
      throw ''
        Missing required attribute: forbiddenVlanRanges

        This compiler does NOT invent forbidden VLAN policy defaults.

        Fix: set an explicit policy in your inputs, e.g.

          forbiddenVlanRanges = [ ];

        Or provide ranges:

          forbiddenVlanRanges = [ { from = 2; to = 9; } ];
      ''
    else if model.forbiddenVlanRanges == null then
      throw ''
        forbiddenVlanRanges must be a list (or an explicit empty list).

        Fix: set:

          forbiddenVlanRanges = [ ];
      ''
    else if !builtins.isList model.forbiddenVlanRanges then
      throw ''
        forbiddenVlanRanges must be a list of { from = <int>; to = <int>; }.

        Fix: set:

          forbiddenVlanRanges = [ ];
      ''
    else
      model.forbiddenVlanRanges;

  _assertForbiddenRangesShape =
    lib.assertMsg
      (
        builtins.isList forbiddenRanges
        && lib.all (
          r: builtins.isAttrs r && r ? from && r ? to && builtins.isInt r.from && builtins.isInt r.to
        ) forbiddenRanges
      )
      ''
        forbiddenVlanRanges must be a list of { from = <int>; to = <int>; }.

        Fix: set:

          forbiddenVlanRanges = [ ];
      '';

  inRange = r: v: v >= r.from && v <= r.to;

  badVlans = lib.filter (v: lib.elem v reserved || lib.any (r: inRange r v) forbiddenRanges) allVlans;

  isPolicyCoreName =
    l:
    (l.kind or null) == "p2p"
    && ((l.name or "") == "policy-core" || lib.hasPrefix "policy-core-" (l.name or ""));

  badPolicyCore = lib.filter (
    l: isPolicyCoreName l && (l ? vlanId) && (l.vlanId < 0 || l.vlanId > 255)
  ) (lib.attrValues links);

in
builtins.seq _assertForbiddenRangesShape (
  if badVlans != [ ] then
    throw "Topology violates site VLAN policy. Forbidden VLAN(s): ${lib.concatStringsSep ", " (map toString badVlans)}"
  else if badPolicyCore != [ ] then
    throw "policy-core VLAN ID must be in range 0..255 for IPv6 transit encoding."
  else
    model
)
