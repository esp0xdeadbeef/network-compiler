{ lib, model }:

let
  links = model.links or { };

  allVlans = lib.unique (
    lib.concatMap (l: lib.optional (l ? vlanId) l.vlanId) (lib.attrValues links)
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

  bad = lib.filter (v: lib.elem v reserved || lib.any (r: inRange r v) forbiddenRanges) allVlans;

in
if bad != [ ] then
  throw "Topology violates site VLAN policy. Forbidden VLAN(s): ${lib.concatStringsSep ", " (map toString bad)}"
else
  model
