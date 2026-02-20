{ lib }:

site:

let
  check = cond: msg: if cond then true else throw msg;

  nodes = site.nodes or { };
  links = site.links or [ ];

  nodeNames = builtins.attrNames nodes;

  validRoles = [
    "core"
    "policy"
    "access"
  ];

  coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") nodeNames;

  _nonEmpty = check (nodeNames != [ ]) "site must define at least one node";

  _roles = lib.mapAttrsToList (
    name: n: check (lib.elem (n.role or null) validRoles) "node '${name}' has invalid or missing role"
  ) nodes;

  _coreSpecialization = lib.forEach coreNodes (
    name:
    check (
      nodes.${name} ? isp
    ) "core node '${name}' must define 'isp' (core nodes require container specialization)"
  );

  _access = lib.mapAttrsToList (
    name: n:
    if (n.role or null) == "access" then
      check (
        n ? networks && builtins.isAttrs n.networks && n.networks != { }
      ) "access node '${name}' must define networks.<name> = { ipv4, ipv6, kind }"
    else
      check (!(n ? networks)) "only access nodes may define networks (offender: ${name})"
  ) nodes;

  _links = map (
    pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;
    in
    check (lib.elem a nodeNames) "link references unknown node '${a}'"
    && check (lib.elem b nodeNames) "link references unknown node '${b}'"
  ) links;

in
site
