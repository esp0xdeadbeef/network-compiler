{ lib }:

topo:

let
  rc = import ./route-classes.nix { inherit lib; };

  links = topo.links or { };

  isDefault4 = r: (r.dst or null) == "0.0.0.0/0";
  isDefault6 = r: (r.dst or null) == "::/0";

  hasDefault =
    ep:
    let
      r4 = ep.routes4 or [ ];
      r6 = ep.routes6 or [ ];
    in
    (lib.any isDefault4 r4) || (lib.any isDefault6 r6);

  overlayClassForLink =
    l:
    let
      nm = l.name or null;
      ok = nm != null && builtins.isString nm && nm != "" && nm != "wan";
    in
    if ok then "overlay:${nm}" else null;

  capsForEndpoint =
    lname: l: ep:
    let
      explicit = ep.capabilities or null;
      fromLink = l.capabilities or null;

      inferred =
        if (l.kind or null) == "wan" && hasDefault ep then
          let
            ov = overlayClassForLink l;
          in
          [
            "default"
            "internet"
          ]
          ++ lib.optional (ov != null) ov
        else
          [ "none" ];

      chosen =
        if explicit != null then
          explicit
        else if fromLink != null then
          fromLink
        else
          inferred;
    in
    rc.normalize chosen;

  capsForLink =
    lname: l:
    let
      eps = lib.attrValues (l.endpoints or { });
      perEp = map (ep: capsForEndpoint lname l ep) eps;
      merged = lib.unique (lib.flatten perEp);

      pruned = if lib.any (c: c != "none") merged then lib.filter (c: c != "none") merged else merged;
    in
    rc.normalize pruned;

  byLink = lib.mapAttrs capsForLink links;

  allCaps = rc.normalize (lib.flatten (lib.attrValues byLink));

in
{
  inherit byLink allCaps;
}
