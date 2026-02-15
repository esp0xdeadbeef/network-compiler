# ./lib/query/wan.nix
{ lib }:

routed:

let
  sanitize = import ./sanitize.nix { inherit lib; };

  wanLinks = lib.filterAttrs (_: l: (l.kind or null) == "wan") (routed.links or { });

in
sanitize {
  wans = lib.mapAttrs (
    lname: l:
    {
      name = l.name or lname;
      vlanId = l.vlanId or null;
      carrier = l.carrier or null;

      endpoints = lib.mapAttrs (
        _node: ep:
        {
          addr4 = ep.addr4 or null;
          addr6 = ep.addr6 or null;
          routes4 = ep.routes4 or [ ];
          routes6 = ep.routes6 or [ ];
        }
      ) (l.endpoints or { });
    }
  ) wanLinks;
}

