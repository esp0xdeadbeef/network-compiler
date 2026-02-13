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
    model.forbiddenVlanRanges or [
      {
        from = 2;
        to = 9;
      }
    ];

  inRange = r: v: v >= r.from && v <= r.to;

  badVlans = lib.filter (v: lib.elem v reserved || lib.any (r: inRange r v) forbiddenRanges) allVlans;

  badPolicyCore = lib.filter (
    l:
    (l.kind or null) == "p2p"
    && (l.name or "") == "policy-core"
    && (l ? vlanId)
    && (l.vlanId < 0 || l.vlanId > 255)
  ) (lib.attrValues links);

in
if badVlans != [ ] then
  throw "Topology violates site VLAN policy. Forbidden VLAN(s): ${lib.concatStringsSep ", " (map toString badVlans)}"
else if badPolicyCore != [ ] then
  throw "policy-core VLAN ID must be in range 0..255 for IPv6 transit encoding."
else
  model
