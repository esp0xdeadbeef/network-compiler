{ lib }:

let
  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts != 2 then
      throw "invariants: invalid CIDR '${toString cidr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  isRole = role: n: ((n.role or "") == role);

  nodeNamesByRole = role: nodes: builtins.attrNames (lib.filterAttrs (_: n: isRole role n) nodes);

  linksForNode =
    node: links:
    lib.filter (
      lname:
      let
        l = links.${lname};
        eps = l.endpoints or { };
      in
      eps ? "${node}"
    ) (builtins.attrNames links);

  p2pLinksForNode =
    node: links:
    lib.filter (
      lname:
      let
        l = links.${lname};
        eps = l.endpoints or { };
      in
      (l.kind or null) == "p2p" && (eps ? "${node}")
    ) (builtins.attrNames links);

  otherEnd =
    node: linkName: link:
    let
      eps = link.endpoints or { };
      ns = builtins.attrNames eps;
    in
    if builtins.length ns != 2 then
      throw "invariants: link '${linkName}' kind=p2p must have exactly 2 endpoints (has ${toString (builtins.length ns)})"
    else if !(lib.elem node ns) then
      throw "invariants: link '${linkName}' does not include node '${node}'"
    else if builtins.elemAt ns 0 == node then
      builtins.elemAt ns 1
    else
      builtins.elemAt ns 0;

  assert_ = cond: msg: if cond then true else throw msg;

  checkP2PAddrs =
    policyName: links:
    let
      p2ps = lib.filterAttrs (_: l: (l.kind or null) == "p2p") links;

      checkOne =
        lname: l:
        let
          eps = l.endpoints or { };
          ns = builtins.attrNames eps;

          _len =
            assert_ (builtins.length ns == 2)
              "invariants: p2p link '${lname}' must have exactly 2 endpoints (has ${toString (builtins.length ns)})";

          a = builtins.elemAt ns 0;
          b = builtins.elemAt ns 1;

          ea = eps.${a} or { };
          eb = eps.${b} or { };

          a4 = ea.addr4 or null;
          b4 = eb.addr4 or null;
          a6 = ea.addr6 or null;
          b6 = eb.addr6 or null;

          _have4 = assert_ (
            a4 != null && b4 != null
          ) "invariants: p2p link '${lname}' endpoints must both have addr4";

          _have6 = assert_ (
            a6 != null && b6 != null
          ) "invariants: p2p link '${lname}' endpoints must both have addr6";

          p4a = (splitCidr a4).prefix;
          p4b = (splitCidr b4).prefix;
          p6a = (splitCidr a6).prefix;
          p6b = (splitCidr b6).prefix;

          _p4 =
            assert_ (p4a == 31 && p4b == 31)
              "invariants: p2p link '${lname}' addr4 must be /31 on both ends (got ${toString p4a} and ${toString p4b})";

          _p6 =
            assert_ (p6a == 127 && p6b == 127)
              "invariants: p2p link '${lname}' addr6 must be /127 on both ends (got ${toString p6a} and ${toString p6b})";

          _adj =
            assert_ (a == policyName || b == policyName)
              "invariants: illegal p2p adjacency on '${lname}': '${a}' <-> '${b}' (p2p must include '${policyName}')";
        in
        true;

    in
    lib.all (x: x) (lib.mapAttrsToList checkOne p2ps);

  checkAccessNetworks =
    nodes:
    let
      offenders = lib.filter (
        n: (nodes.${n}.networks or null) != null && ((nodes.${n}.role or "") != "access")
      ) (builtins.attrNames nodes);
    in
    assert_ (offenders == [ ])
      "invariants: only access nodes may define networks; offenders: ${lib.concatStringsSep ", " offenders}";

  checkPolicyNode =
    nodes:
    let
      hasPolicyName = nodes ? "s-router-policy";
      policyNode = nodes."s-router-policy" or null;

      policyByRole = nodeNamesByRole "policy" nodes;

      _mustExist = assert_ hasPolicyName "invariants: missing required node 's-router-policy'";

      _mustBeRole = assert_ (
        (policyNode.role or "") == "policy"
      ) "invariants: node 's-router-policy' must have role='policy'";

      _exactlyOne =
        assert_ (builtins.length policyByRole == 1 && lib.head policyByRole == "s-router-policy")
          "invariants: exactly one policy node is required and it must be named 's-router-policy' (found policy role nodes: ${lib.concatStringsSep ", " policyByRole})";
    in
    "s-router-policy";

  checkStarAndDegrees =
    policyName: nodes: links:
    let
      nonPolicy = lib.filter (n: n != policyName) (builtins.attrNames nodes);

      rolesOk =
        n:
        let
          r = nodes.${n}.role or "";
        in
        r == "core" || r == "access" || r == "policy";

      badRoles = lib.filter (n: !rolesOk n) (builtins.attrNames nodes);

      _roles =
        assert_ (badRoles == [ ])
          "invariants: unsupported node role(s) (allowed: core, access, policy). Offenders: ${
            lib.concatStringsSep ", " (map (n: "${n}=${nodes.${n}.role or ""}") badRoles)
          }";

      checkNonPolicy =
        n:
        let
          r = nodes.${n}.role or "";

          p2pLs = p2pLinksForNode n links;
          allLs = linksForNode n links;

          _mustHaveP2P = assert_ (
            p2pLs != [ ]
          ) "invariants: node '${n}' role='${r}' must have a p2p link to '${policyName}'";

          _p2pDegree1 =
            assert_ (builtins.length p2pLs == 1)
              "invariants: node '${n}' role='${r}' must have exactly 1 p2p link (found ${toString (builtins.length p2pLs)}: ${lib.concatStringsSep ", " p2pLs})";

          onlyP2P = lib.head p2pLs;
          neigh = otherEnd n onlyP2P links.${onlyP2P};

          _neighborIsPolicy =
            assert_ (neigh == policyName)
              "invariants: node '${n}' role='${r}' p2p neighbor must be '${policyName}' (found '${neigh}' via '${onlyP2P}')";

          _totalCap =
            if r == "core" || r == "access" then
              assert_ (builtins.length allLs <= 2)
                "invariants: node '${n}' role='${r}' may have at most 2 links total (found ${toString (builtins.length allLs)}: ${lib.concatStringsSep ", " allLs})"
            else
              true;
        in
        true;

      _nonPolicyChecks = lib.all (x: x) (map checkNonPolicy nonPolicy);

      policyLinks = linksForNode policyName links;

      _policyMinDegree =
        assert_ (builtins.length policyLinks >= 2)
          "invariants: '${policyName}' must have at least 2 links (found ${toString (builtins.length policyLinks)}: ${lib.concatStringsSep ", " policyLinks})";

      p2pCount = builtins.length (
        builtins.attrNames (lib.filterAttrs (_: l: (l.kind or null) == "p2p") links)
      );

      _p2pCount =
        assert_ (p2pCount == builtins.length nonPolicy)
          "invariants: expected exactly one p2p link per non-policy node (expected ${toString (builtins.length nonPolicy)}, got ${toString p2pCount})";
    in
    true;

in
{
  checkSite =
    { site, links }:
    let
      nodes = site.nodes or { };

      _mustHaveNodes = assert_ (
        builtins.isAttrs nodes && (builtins.attrNames nodes) != [ ]
      ) "invariants: site must define non-empty nodes";

      _mustHaveLinks = assert_ (builtins.isAttrs links) "invariants: internal error: links must be an attrset";

      policyName = checkPolicyNode nodes;

      _networks = checkAccessNetworks nodes;

      _p2p = checkP2PAddrs policyName links;

      _star = checkStarAndDegrees policyName nodes links;
    in
    true;
}
