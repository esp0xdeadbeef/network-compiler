{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isRole = role: n: (n.role or "") == role;

  nodeNamesByRole = role: nodes: builtins.attrNames (lib.filterAttrs (_: n: isRole role n) nodes);

  accessNetworksDisjoint = import ./node-roles/access-networks-disjoint.nix { inherit lib; };

in
{
  check =
    { site, ... }:
    let
      nodes = site.nodes or { };

      _mustHaveNodes = assert_ (
        builtins.isAttrs nodes && (builtins.attrNames nodes) != [ ]
      ) "invariants(node-roles): site must define non-empty nodes";

      supported = [
        "core"
        "access"
        "policy"
      ];

      badRoles = lib.filter (
        n:
        let
          r = nodes.${n}.role or null;
        in
        r == null || !(lib.elem r supported)
      ) (builtins.attrNames nodes);

      _rolesOk =
        assert_ (badRoles == [ ])
          "invariants(node-roles): unsupported or missing role on node(s): ${
            lib.concatStringsSep ", " (map (n: "${n}=${nodes.${n}.role or "null"}") badRoles)
          }";

      policyNodes = nodeNamesByRole "policy" nodes;

      _exactlyOnePolicy = assert_ (
        builtins.length policyNodes == 1
      ) "invariants(node-roles): exactly one node with role='policy' is required";

      offenders = lib.filter (
        n:
        let
          nets = nodes.${n}.networks or null;
        in
        nets != null && (nodes.${n}.role or "") != "access"
      ) (builtins.attrNames nodes);

      _accessOnlyNetworks = assert_ (
        offenders == [ ]
      ) "invariants(node-roles): only access nodes may define networks";

      _accessDisjoint = accessNetworksDisjoint.check { inherit nodes; };
    in
    true;
}
