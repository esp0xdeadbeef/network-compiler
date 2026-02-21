{ lib }:

site:

let

  units = site.nodes or { };

  accessUnit =
    let
      names = builtins.attrNames units;
      isAccess = n: ((units.${n}.role or null) == "access");
      matches = lib.filter isAccess names;
    in
    if builtins.length matches >= 1 then builtins.elemAt matches 0 else null;

  owned = site.processCell.owned or { };
  tenants = owned.tenants or [ ];
  services = owned.services or [ ];

  segments = {
    tenants = tenants;
    services = services;
  };

  attachments =
    if accessUnit == null then
      [ ]
    else
      map (t: {
        segment = "tenants:${t.name}";
        unit = accessUnit;
      }) tenants;

  transitLinks =
    if site.processCell ? transit && site.processCell.transit ? links then
      site.processCell.transit.links
    else if site ? links then
      site.links
    else
      [ ];

  transitPool = site.p2p-pool or null;

in
{
  enterprise = site.enterprise or "default";

  inherit segments attachments;

  transit = {
    links = transitLinks;
    pool = transitPool;
  };
}
